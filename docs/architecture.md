# Architecture decisions

## 1. Function URLs, not API Gateway

The requirement is two simple URL-accessible Lambdas. Function URLs give each service a managed HTTPS endpoint on AWS without an additional routing/control plane or API Gateway request charge. LocalStack exposes equivalent HTTP routes for the demo.

Choose **API Gateway HTTP API** when there is a requirement for one API with routes, JWT authorizers, centralized throttling, or API access logs. Choose REST API only for features that actually need it. Check the chosen API type/features in the free emulator before changing the demo.

Trade-offs accepted: two endpoint names, IAM rather than JWT auth in AWS, no per-client quotas, custom domains, CORS, or gateway request validation. The validator must receive malformed JSON, so a gateway must not reject it before invocation. A Function URL's IAM auth protects access but does not make its network endpoint private.

## 2. One narrowly scoped module

The module owns a Python 3.14 deployment pattern, not every possible Lambda configuration. Standard-library sources are archived with fixed permissions, and `source_code_hash` makes code updates visible to Terraform. Generated ZIPs are ignored under `.terraform/` and named by source-content hash so packaging another revision does not overwrite a saved plan's artifact. Bytecode and tests outside the service directory are not packaged. Functions default to arm64 (cheaper on AWS); locally, `make` picks the host's architecture so LocalStack never emulates.

The two roots repeat a short module call to share `services.json`. This is preferable to a generic environment framework or nested IAM/logging/naming modules. Local and AWS roots have different providers, credentials, names, and state files. No environment flag can accidentally switch the local provider to real AWS.

The two roots commit their provider lock files; the reusable module does not, following Terraform convention. LocalStack is pinned by version **and image digest** to an account-free community image; upgrading it is an explicit compatibility test. Python's managed runtime/base image still receives patch updates: pinning the minor runtime is not a promise of byte-for-byte AWS runtime reproducibility.

## 3. Three different permission boundaries

1. **Deployment identity:** Terraform's caller provisions infrastructure and passes the execution roles to Lambda. This is an operator/CI permission, not an application permission.
2. **Execution role:** one role per Lambda, trusted only by the Lambda service. It can create log streams and write events only within its own pre-created log group. It has no application AWS API permissions and cannot create arbitrary log groups.
3. **Invocation identity:** AWS URLs default to `AWS_IAM`. Approved same-account callers need an identity policy granting both `lambda:InvokeFunctionUrl` and URL-only `lambda:InvokeFunction`; `caller_policy` is an output, not an automatic grant.

Public access is explicit. The public resource policy also includes both required actions, with the second restricted by `lambda:InvokedViaFunctionUrl`. A wildcard principal is intentional only for the public URL, never a wildcard execution policy.

## 4. Shared HTTP handling, tiny business logic

A small adapter is included in both ZIPs because method checks, encoding, limits, safe errors, and logging are identical. It accepts the Function URL event format, decodes UTF-8/base64 once, and invokes a plain string operation. It is not a router or a general web framework.

The JSON parser checks syntax, rejects Python's nonstandard constants, and avoids integer/float conversion limits because values are never used. An invalid JSON document is a successful validation result, not an exception to page on; it includes the parser's reason and position, never the input. Oversized input and excessive parser nesting have distinct processing-limit responses.

## 5. Observability without unowned alerts

Structured request logs have request ID, service, status, outcome, and elapsed handler time. Error logs retain exception type and stack locations, not messages or source lines that might expose input. The measured handler time excludes cold-start and URL overhead; use native Duration/URL metrics for those views. Log retention is 14 days by default.

AWS publishes `Invocations`, `Errors`, `Throttles`, `Duration`, and `Url4xxCount`/`Url5xxCount` per function without configuration. Alarms are intentionally not created: an alarm without an owning team, routing, and agreed thresholds is noise. When that ownership exists, alarm on both `Errors` and `Url5xxCount`, because a returned HTTP 500 does not count as a Lambda execution error.

## Evidence

`make check` tests behavior and security-relevant Terraform configuration without AWS credentials. `make smoke` tests actual Function URL routing into packaged Lambda containers, including binary transport and error responses. The CI drift check requires an empty plan after deployment, and cleanup runs even if earlier steps fail. For what this does not prove, see the README and [AWS production gates](aws.md#before-production).
