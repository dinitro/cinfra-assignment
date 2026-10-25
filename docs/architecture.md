# Architecture

## Delivery model

`services.json` is the small service catalog. Each entry is instantiated by the reusable `lambda-service` Terraform module, which packages the handler and creates:

- one Python 3.14 Lambda;
- one Lambda Function URL;
- one execution role; and
- one CloudWatch log group with explicit retention.

The local and AWS roots use separate providers, credentials, names, and state. Local commands therefore cannot silently target AWS.

## Function URLs

Function URLs meet the requirement without adding API Gateway routing or request charges. AWS URLs use `AWS_IAM` by default; the local root explicitly enables public access because it runs on loopback. Use API Gateway HTTP API if the services later need shared routes, JWT authorization, centralized throttling, access logs, or a custom domain.

## Permission boundaries

- An operator supplies a short-lived deployment identity; this project does not provision CI access or a deployment role. Scope its provisioning permissions to this stack and restrict `iam:PassRole` to the execution roles with `iam:PassedToService = lambda.amazonaws.com`.
- Each execution role trusts only `lambda.amazonaws.com` and can write only to its own log group.
- Same-account AWS callers receive both required Function URL actions through the generated `caller_policy`; URL-only enforcement needs a resource-based policy for a known caller principal.
- Public access is an explicit variable and is never enabled by the AWS default.

## Packaging and application code

A small shared HTTP adapter handles method checks, UTF-8/base64 decoding, size limits, safe error responses, request IDs, and structured logs. The service handlers only implement their business operation. ZIPs contain standard-library Python sources and the adapter; `source_code_hash` makes source changes visible to Terraform.

## Observability

Requests produce one structured log record with service, request ID, status, outcome, and duration. Request bodies and exception messages are not logged. Lambda's native metrics provide invocation, error, throttle, duration, and Function URL error views. Alarms are intentionally outside this assignment because they need an owning team and thresholds.
