# Operations

## Logs and request correlation

Every handler-generated response includes `x-request-id`; the same value appears in the structured application log. Bodies are never logged. AWS can reject requests before the handler runs, so authentication failures, throttling, and platform errors do not carry this application-level guarantee.

```bash
make logs SERVICE=length
make logs SERVICE=json-validator
```

In AWS, get the exact log group name and tail it:

```bash
export AWS_PROFILE=sandbox
export REGION=eu-central-1
LOG_GROUP=$(terraform -chdir=infra/aws output -json log_groups | \
  python3 -c 'import json,sys; print(json.load(sys.stdin)["length"])')
aws logs tail "$LOG_GROUP" --since 10m --region "$REGION" --profile "$AWS_PROFILE"
```

Useful Logs Insights fields are `request_id`, `service`, `status`, `outcome`, `duration_ms`, `error_type`, and `stack`.

## Metrics

Lambda provides `Invocations`, `Errors`, `Throttles`, `Duration`, `Url4xxCount`, and `Url5xxCount`. A JSON validation result of `{"valid":false}` is a normal HTTP 200 response. The adapter catches unexpected exceptions and returns HTTP 500 normally, so these failures appear in `Url5xxCount` but not necessarily in Lambda's `Errors` metric. Add alarms only after ownership, thresholds, and notification routing are agreed.

## Local troubleshooting

| Symptom | Action |
|---|---|
| Docker is unavailable | Start Docker Desktop, OrbStack, or the Linux daemon; check `docker info`. |
| LocalStack cannot start Lambda containers | Check `docker compose logs` and Docker socket access. |
| Function URL DNS fails | Use the README `curl --connect-to` form; preserve the LocalStack `Host` header. |
| A proxy intercepts local requests | Use `curl --noproxy '*'`; the smoke script disables proxies. |
| HTTP 500/502 | Run `make logs SERVICE=<name>` and inspect LocalStack logs. |
| LocalStack was recreated | Run `make up` followed by `make deploy`; Terraform state is separate from the container. |
| Terraform wants real AWS credentials during checks | Stop: `make check` uses mocked providers and should not need AWS credentials. |

LocalStack mounts the Docker socket so it can start Lambda containers. That gives it root-equivalent control of the host Docker daemon; use it only in a trusted development environment or isolated CI runner. The compose port is bound to `127.0.0.1`.

## Cleanup and rollback

```bash
make destroy
make down
```

For AWS, review `terraform -chdir=infra/aws plan -destroy` before destroying; managed log groups and their contents are deleted too. Renaming or removing a `services.json` key replaces or removes the corresponding service, changing its endpoint and deleting the old logs. Export any required evidence first. To roll back code, restore the last known-good revision, review the plan, and apply it. This project does not create Lambda aliases or canary releases, so rollback is a source deployment rather than an instant traffic switch.
