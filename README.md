# Cinfra Lambda services

This project deploys the two services from the assignment:

| Service | Request | Response |
|---|---|---|
| `length` | UTF-8 text | `{"length": 5}` |
| `json-validator` | UTF-8 JSON text | `{"valid": true}` or `{"valid": false, ...}` |

Each service is a Python 3.14 Lambda exposed through a Lambda Function URL. Terraform packages the handlers, creates least-privilege execution roles, and configures bounded CloudWatch log retention.

Developers own handlers, tests, and `services.json`. The platform owns packaging, IAM, URLs, logging, and runtime defaults.

## Requirement mapping

| Requirement | Implementation |
|---|---|
| Two Lambdas | `functions/length`, `functions/json_validator` |
| URL access | AWS Lambda Function URLs |
| Local testing | LocalStack and real HTTP smoke tests |
| Deployment | Reusable module in `infra/modules/lambda-service` |
| Configuration | `services.json` |
| Verification | Python tests, Terraform tests, and CI smoke tests |

## Run locally

Prerequisites: Docker, Compose with `up --wait`, Terraform 1.16.6, Python 3.14, Make, and Bash.

```bash
make check       # unit, formatting, validation, and mocked Terraform tests
make up          # start LocalStack
make deploy      # deploy both Lambdas and print their URLs
make smoke       # invoke the deployed URLs through LocalStack
make logs SERVICE=length
```

LocalStack uses dummy credentials and does not require an AWS account or paid features. The local URLs are public only on loopback:

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

`--connect-to` keeps the LocalStack hostname in the `Host` header while connecting to loopback. Omit it when `*.localhost.localstack.cloud` already resolves locally. Never use this option with an AWS URL.

### Local cleanup

After trying the endpoints, remove the local resources and stop LocalStack:

```bash
make destroy
make down
```

This also deletes the local logs.

## HTTP contract

Send the body itself, not a JSON envelope, with `POST` and `Content-Type: text/plain; charset=utf-8`. Bodies transported as base64 by the Function URL integration are decoded first.

- `length` counts Unicode code points, not UTF-8 bytes or grapheme clusters: `é🐈` is 2. Input is not trimmed or normalized.
- `json-validator` checks JSON syntax, not a business schema. Scalar values and duplicate object keys are accepted; `NaN`, infinity, comments, and trailing commas are not.

| Input or outcome | HTTP | JSON body |
|---|---:|---|
| Length of `hello` | 200 | `{"length":5}` |
| Empty body, length service | 200 | `{"length":0}` |
| Valid JSON, including scalars | 200 | `{"valid":true}` |
| Invalid JSON, e.g. `{"a":}` | 200 | `{"valid":false,"reason":"Expecting value","line":1,"column":6}` |
| Invalid UTF-8 or base64 transport | 400 | `{"error":"invalid_utf8_body"}` |
| Non-POST method | 405 | `{"error":"method_not_allowed"}`, with `Allow: POST` |
| Body over 64 KiB of decoded UTF-8 bytes | 413 | `{"error":"body_too_large"}` |
| JSON nesting exceeds parser capacity | 422 | `{"error":"json_too_deep"}` |
| Unexpected application failure | 500 | `{"error":"internal_error"}` |

Invalid JSON is a successful validation result, not an HTTP error. Reasons include 1-based line/column positions when available and never echo the input. Parser capacity is a processing limit, not proof of invalid JSON; Python 3.14 handles all nesting that fits this body limit, so 422 is a safety net.

Handler-generated responses are JSON and include `x-request-id` and `Cache-Control: no-store`. Request bodies are never logged. AWS authentication failures, throttling, and platform errors can occur before the handler runs and do not follow this application response contract.

## Add a service

1. Add `functions/uppercase/handler.py`, using the shared HTTP adapter:

   ```python
   from platform_http import handle

   def handler(event, context):
       return handle(event, context, lambda text: {"result": text.upper()})
   ```

   The operation receives decoded text and returns a JSON-serializable dictionary. Terraform adds `platform_http.py` to the ZIP; do not copy it into the service directory.

2. Add a named entry to `services.json`, keeping the existing services:

   ```json
   {
     "length": {"source_dir": "functions/length"},
     "json-validator": {"source_dir": "functions/json_validator"},
     "uppercase": {"source_dir": "functions/uppercase"}
   }
   ```

3. Add unit tests under `tests/`. Follow `tests/test_handlers.py`, including its runtime-directory import-path setup so the packaged adapter is available locally.
4. Add a success case to `DeployedServices.test_services` in `scripts/smoke.py`:

   ```python
   self.assertEqual(self.invoke("uppercase", "hello"), {"result": "HELLO"})
   ```

   Common method and body-limit checks run automatically for every deployed service; they do not replace service-specific success tests.

5. Run `make check`, `make up`, `make deploy`, `make smoke`, and `make plan`. Code changes are packaged automatically; no IAM or URL resources need to be copied.

Service names use letters, numbers, underscores, or hyphens, and the generated name including its deployment prefix must fit AWS's 64-character limit. This pattern supports standard-library Python sources only.

**Destructive changes:** renaming or removing a catalog key replaces or removes that service, changes its endpoint, and deletes its managed logs. Review the AWS plan and export any logs you need before applying.

## Deploy to AWS

The AWS root is separate from LocalStack and uses normal AWS credentials. URLs require `AWS_IAM` authentication by default; `public_urls = true` is an explicit opt-in to anonymous internet access and its associated abuse and cost risk.

```bash
cp infra/aws/terraform.tfvars.example infra/aws/terraform.tfvars
# Set aws_account_id, then check this revision and review the plan.
make check
terraform -chdir=infra/aws init -lockfile=readonly
terraform -chdir=infra/aws plan -out=deploy.tfplan
terraform -chdir=infra/aws apply deploy.tfplan
terraform -chdir=infra/aws output -json service_urls
```

See [AWS deployment](docs/aws.md) for credential setup, IAM invocation, and cleanup. AWS deployment is manual; CI only validates configuration and tests LocalStack. AWS CI access and remote-state provisioning are intentionally outside this assignment.

## Design and scope

- Function URLs are sufficient for two independent endpoints; use API Gateway if routing, JWT authorization, centralized throttling, or a custom domain becomes a requirement.
- Local and AWS Terraform roots have separate providers and state, so local commands cannot accidentally target AWS.
- The execution roles can only write to their own pre-created log groups and have no application AWS permissions.
- The generated same-account caller policy grants both required Lambda actions; URL-only enforcement needs a resource-based policy for a known caller principal.
- The assignment uses standard-library Python only. Third-party dependencies or non-Python assets would need a build step.

## Verification status

`make check`, `make deploy`, `make smoke`, and a converged `make plan` pass locally against LocalStack. `.github/workflows/ci.yml` runs the same checks on pushes and pull requests. The AWS root is validated and covered by mocked-provider tests, but no real AWS apply was performed; AWS IAM behavior and billing were therefore not independently verified.

## Repository map

| Path | Purpose |
|---|---|
| `functions/` | Business handlers |
| `services.json` | Service catalog |
| `infra/modules/lambda-service/` | Packaging, IAM, logging, and URLs |
| `infra/local/` | LocalStack provider and state |
| `infra/aws/` | AWS provider, account guard, and IAM URLs |
| `tests/`, `scripts/smoke.py` | Unit and deployed HTTP tests |
| `docs/` | Architecture, operations, and direct AWS deployment |

More detail is in [architecture](docs/architecture.md), [operations](docs/operations.md), and [AWS deployment](docs/aws.md).
