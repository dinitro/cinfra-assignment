# Self-service Lambda deployment

Two small HTTP services, one reusable Terraform module, and a local demo that needs **no AWS account, LocalStack account, paid features, or Python dependencies**.

> Developers own their code, tests, and an entry in `services.json`. The infrastructure team owns packaging, IAM, runtime defaults, URLs, and operational guardrails.

```text
code + services.json ── Terraform ── lambda-service module × 2
                                     ├─ Python 3.14 Lambda
                                     ├─ Function URL
                                     ├─ dedicated execution role
                                     └─ retained CloudWatch log group

Local: LocalStack, dummy credentials, public demo URLs on loopback
AWS:   separate root/state, IAM-authenticated URLs by default
```

## Run the demo

Prerequisites:

- Docker with a running daemon and Compose supporting `up --wait`
- Terraform **1.16.6** (see `.terraform-version`; newer 1.x works)
- Python **3.14**, matching the Lambda runtime, plus Make and Bash on Linux or macOS

The first run downloads images and providers and can take several minutes. Everything runs in `eu-central-1` (Frankfurt). `make` matches the Lambda architecture to your CPU (arm64 on Apple Silicon, x86_64 on GitHub runners), so nothing is emulated; AWS deployments default to the cheaper arm64.

```bash
make check       # unit tests, terraform fmt/validate, mocked infrastructure tests
make up          # start the pinned, free LocalStack image
make deploy      # package and deploy both Lambdas; print their URLs
make smoke       # actual HTTP requests through LocalStack into Lambda containers
make urls        # print the service URLs again
make logs SERVICE=length   # structured request logs for one service
```

### Try it yourself

Local URLs are predictable: `http://<service>.lambda-url.eu-central-1.localhost.localstack.cloud:4566/`, stable across destroy/deploy. Always send `Content-Type: text/plain`; curl's default form encoding alters the body.

```bash
curl --noproxy '*' --connect-to '::127.0.0.1:4566' \
  http://length.lambda-url.eu-central-1.localhost.localstack.cloud:4566/ \
  -H 'Content-Type: text/plain; charset=utf-8' --data-binary 'hello'
# {"length": 5}

curl --noproxy '*' --connect-to '::127.0.0.1:4566' \
  http://json-validator.lambda-url.eu-central-1.localhost.localstack.cloud:4566/ \
  -H 'Content-Type: text/plain; charset=utf-8' --data-binary '{"a":1}'
# {"valid": true}

curl --noproxy '*' --connect-to '::127.0.0.1:4566' \
  http://json-validator.lambda-url.eu-central-1.localhost.localstack.cloud:4566/ \
  -H 'Content-Type: text/plain; charset=utf-8' --data-binary '{"a":}'
# {"valid": false, "reason": "Expecting value", "line": 1, "column": 6}
```

`--connect-to` changes the connection address, **not** the original Host header used for Lambda routing. Without DNS restrictions you can omit it. Do not use this local-only option for AWS URLs. The smoke runner does the same and refuses real AWS URLs.

```bash
make plan        # "No changes" after deployment; exits non-zero on drift
make destroy     # deletes the local functions, permissions, roles, and logs
make down        # stops LocalStack; do this AFTER destroy
```

All Make deployment/destruction targets operate on **`infra/local` only**. LocalStack is ephemeral: container removal loses its resources, not the ignored Terraform state on disk. If stopped before destroy, start it and run `make deploy` to reconcile. Never delete real AWS state to resolve drift.

## HTTP contract

Send the **string itself**, not a JSON envelope, to each function URL with `POST`. Use UTF-8 `text/plain`. Bodies transported as base64 by the Function URL integration are decoded before processing. There is no path routing or browser CORS configuration.

| Case | HTTP | JSON response |
|---|---:|---|
| Length of `hello` | 200 | `{"length":5}` |
| Empty body, length service | 200 | `{"length":0}` |
| Valid JSON, including scalars | 200 | `{"valid":true}` |
| Invalid/empty JSON | 200 | `{"valid":false,"reason":"Expecting value","line":1,"column":6}` |
| Non-POST method | 405 | `{"error":"method_not_allowed"}`, `Allow: POST` |
| Invalid UTF-8/base64 | 400 | `{"error":"invalid_utf8_body"}` |
| Body over 64 KiB of decoded UTF-8 bytes | 413 | `{"error":"body_too_large"}` |
| Nesting exceeds the Python JSON parser's capacity | 422 | `{"error":"json_too_deep"}` |
| Unexpected application failure | 500 | `{"error":"internal_error"}` |

- Length counts **Unicode code points**, not bytes or grapheme clusters: `é🐈` is 2; `e` followed by a combining accent is also 2. Input is not normalized or trimmed.
- Validation checks JSON syntax, not a business schema. Objects, arrays, strings, numbers, booleans, and null are valid. Duplicate object keys are accepted; `NaN`, `Infinity`, trailing commas, and comments are not. Invalid results include the parser's `reason` and, where known, 1-based `line`/`column`; reasons never echo the input.
- Number syntax is checked without converting numbers into limited-size integers/floats. Large valid numbers remain valid.
- Parser capacity is runtime-dependent; exceeding it is a request-processing limit, not a claim that the JSON is invalid. On Python 3.14 any nesting that fits in 64 KiB parses, so 422 is a safety net. Requests exceeding AWS's own integration limits can be rejected before the handler runs.
- Responses include `x-request-id` for log correlation and `Cache-Control: no-store`. No request bodies are logged.

## Add or change a service

1. Add `functions/<service>/handler.py` and tests under `tests/`.
2. Use the small shared HTTP adapter supplied by the platform module:

   ```python
   from platform_http import handle

   def handler(event, context):
       return handle(event, context, lambda text: {"result": text.upper()})
   ```

3. Add an entry to `services.json`, for example:

   ```json
   "uppercase": {"source_dir": "functions/uppercase"}
   ```

4. Add an HTTP case in `scripts/smoke.py`, then run `make check`, `make deploy`, and `make smoke`.

No IAM or URL resources need to be copied. Changing code and running `make deploy` updates the ZIP hash automatically. The HTTP adapter is packaged inside each ZIP, not deployed as a separate service/layer; `platform_http.py` is a reserved filename. Unit tests add its source directory to the Python import path.

Optional catalog fields: `memory_mb` (128–1024, default 128), `timeout_seconds` (1–30, default 5), and `log_retention_days` (7/14/30/90, default 14). Function names must fit AWS's 64-character limit after adding the deployment prefix.

This deliberately supports **standard-library Python sources only**. Non-Python assets and third-party packages need an explicit build step before extending this pattern. Removing/renaming a catalog key destroys/replaces that service and its logs; review AWS plans before applying.

## What is where?

| Path | Responsibility |
|---|---|
| `functions/` | Two business handlers |
| `services.json` | Small developer-owned service catalog |
| `infra/modules/lambda-service/` | Packaging, shared HTTP adapter, IAM, logging, URL |
| `infra/local/` | Local-only provider endpoints, dummy credentials, separate state |
| `infra/aws/` | Account guard, IAM-authenticated URLs, caller policy |
| `tests/` | Python unit tests for the handlers and HTTP adapter |
| `infra/modules/lambda-service/tests/`, `infra/aws/tests/` | Terraform tests for the module and the AWS root, with a mocked provider |
| `scripts/smoke.py` | Deployed HTTP integration tests |
| `.github/workflows/ci.yml` | Same checks, local deployment, smoke tests, drift check, unconditional cleanup |

## Deliberately not built

- **API Gateway, custom domains, CORS, frontend:** Function URLs meet the URL requirement. See [architecture](docs/architecture.md#1-function-urls-not-api-gateway) for when to switch.
- **Dashboards, alarms, paging:** structured logs, request IDs, and native Lambda metrics cover these two services; alerting needs an owning team and agreed thresholds first. See [production gates](docs/aws.md#before-production).
- **VPC/NAT, databases, queues, retries, DLQs:** stateless synchronous functions with no private resources or side effects.
- **X-Ray/OpenTelemetry:** there are no downstream calls to trace.
- **Containers, layers, third-party dependencies:** two standard-library Python files plus the adapter.
- **Aliases, canaries, multi-environment framework, AWS deployment pipeline:** disproportionate here; a production pipeline needs an account, approvals, remote state, and OIDC first.

## What is proven

LocalStack proves the packaging, deployment, and HTTP path, **not** AWS IAM enforcement, billing, quotas, or real concurrency. The AWS root is validated and tested with provider mocks only; real AWS verification is a separate gate. CI needs no AWS secrets and never deploys into AWS.

### Further reading

- [Architecture decisions](docs/architecture.md)
- [Operations and troubleshooting](docs/operations.md)
- [Deploying to AWS and production gates](docs/aws.md)
