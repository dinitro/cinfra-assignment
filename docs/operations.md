# Operations and troubleshooting

## Find a request

Use `curl -i` to see the `x-request-id` response header. It matches the structured application log's `request_id`.

```bash
make logs SERVICE=length
make logs SERVICE=json-validator
```

LocalStack CloudWatch Logs receives the application's JSON lines plus the Lambda runtime's START/END/REPORT messages. In AWS, the `log_groups` Terraform output supplies the exact group names. With an approved AWS CLI profile:

```bash
aws logs tail /aws/lambda/cinfra-dev-length --since 10m --region eu-central-1 --profile sandbox
```

CloudWatch Logs Insights query for either group:

```text
fields @timestamp, request_id, service, status, outcome, duration_ms, error_type, stack
| filter request_id = "REPLACE-WITH-RESPONSE-REQUEST-ID"
| sort @timestamp asc
```

Do not turn on payload logging to investigate a failure. Sanitized stack locations identify the failing code; reproduce locally with synthetic data.

## Metrics

AWS records per-function `Invocations`, `Errors`, `Throttles`, `Duration`, and `Url4xxCount`/`Url5xxCount` without extra configuration; view them in the Lambda console's Monitor tab. No alarms are deployed.

- `{"valid":false}` with HTTP 200 is normal application behavior.
- HTTP 4xx processing limits are client errors, not a runtime outage; a sudden increase still merits traffic investigation.
- `Url5xxCount` includes handled 500s that do not appear in `Errors`; correlate with request IDs and sanitized error type/stack.

## Local problems

| Symptom | Check / fix |
|---|---|
| Cannot connect to Docker | Start Docker Desktop/OrbStack or the Linux daemon; run `docker info` |
| Socket not found inside LocalStack | Set `DOCKER_SOCKET_PATH` to the host Unix socket path, then recreate LocalStack |
| Container reports healthy but Lambda creation fails | `docker compose logs --tail=100`; check Docker socket access and access to `public.ecr.aws` |
| Lambda runtime will not start on an unusual CPU | Override detection, e.g. `make deploy LAMBDA_ARCH=x86_64` (needs emulation on ARM hosts) |
| Function URL DNS does not resolve | Use README's `curl --connect-to` form or `make smoke`; preserve the original Host header |
| Proxy intercepts a local URL | Use `curl --noproxy '*'`; the smoke runner disables proxies for its loopback connection |
| HTTP 500/502 | Check `make logs SERVICE=...` and LocalStack logs; look for import errors or runtime startup failure |
| LocalStack was removed but state remains | `make up`, then `make deploy`; Terraform refresh reconciles missing local resources |
| Unexpected resource replacement | Review catalog key/name changes and plan; do not delete state to hide the problem |
| A check requests real AWS credentials | Stop: `make check` uses mocked AWS providers and should not require credentials |

Example for a non-default Unix socket:

```bash
export DOCKER_SOCKET_PATH="$HOME/.orbstack/run/docker.sock"
make up
```

The Docker socket gives LocalStack broad control over the host Docker daemon. Use it only in a trusted development environment or an isolated CI runner. The compose port binds only to `127.0.0.1`; do not expose LocalStack on a shared/public network. Other containers on the same Docker network can still reach it.

## Cleanup and rollback

- Local: `make destroy`, then `make down`. Logs are deleted with the demo.
- AWS: review `terraform -chdir=infra/aws plan -destroy`, then explicitly run `terraform -chdir=infra/aws destroy`. This also deletes managed log groups; export any required evidence first. A remote-state bucket, if used, is managed separately and not deleted.
- Code rollback: restore the last known-good source revision, review the Terraform plan, and apply it. There are no version aliases or atomic/canary rollouts here, so an update can briefly serve old/new code during propagation.
- Timeout and payload limits are not rate limits or budget caps. IAM-authenticated AWS access is the default; public deployment requires an explicit abuse/cost decision.
