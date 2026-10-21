# Deploying to AWS

This is an **optional, billable** deployment. Nothing in the Makefile or CI applies the AWS root.

## Deploy to a sandbox

Use short-lived credentials for a provisioning identity in your own sandbox account (for example via SSO). It manages the stack's Lambda functions, URL policies, execution roles, and log groups; constrain `iam:PassRole` to the execution roles with `iam:PassedToService = lambda.amazonaws.com`. Never commit access keys.

```bash
cp infra/aws/terraform.tfvars.example infra/aws/terraform.tfvars
# Edit aws_account_id and name_prefix (region defaults to eu-central-1); the account guard rejects other accounts.
export AWS_PROFILE=sandbox
aws sts get-caller-identity
terraform -chdir=infra/aws init -lockfile=readonly
terraform -chdir=infra/aws plan -out=deploy.tfplan
terraform -chdir=infra/aws apply deploy.tfplan
terraform -chdir=infra/aws output -json service_urls
```

Clear any inherited `AWS_ENDPOINT_URL*` overrides first; this root has no LocalStack endpoints or dummy credentials, and its state is separate from `infra/local`. Use a unique `name_prefix` per deployment, because IAM role names are account-wide. State is local by default and ignored by git; treat state and plans as sensitive.

## Invoke an IAM-authenticated URL

Default URLs use `AWS_IAM`. Attach the generated `caller_policy` to an approved same-account calling identity:

```bash
terraform -chdir=infra/aws output -raw caller_policy
```

It grants both Function URL invocation actions, scoped to these functions and URL invocation only. Then, with short-lived credentials exported into your shell:

```bash
LENGTH_URL=$(terraform -chdir=infra/aws output -json service_urls | python3 -c 'import json,sys; print(json.load(sys.stdin)["length"])')
curl --aws-sigv4 'aws:amz:eu-central-1:lambda' \
  --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
  -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
  -H 'Content-Type: text/plain; charset=utf-8' \
  --data-binary 'hello' "$LENGTH_URL"
```

Use the region from `terraform.tfvars`. Unsigned requests should be denied; verify that on real AWS.

Setting `public_urls = true` allows anonymous internet access with no rate limit or spending cap. Do not enable it merely to avoid SigV4.

## Before production

- [ ] Confirm the account, environment, ownership, request-volume expectations, and cost budget.
- [ ] Move state to a dedicated private, encrypted, versioned S3 bucket with native locking (`use_lockfile = true`), managed outside this stack.
- [ ] Deploy from CI through a protected environment using GitHub OIDC and a scoped, short-lived deployment role; no repository secrets, no unreviewed pull-request code.
- [ ] Verify signed approved callers succeed, unsigned/unapproved callers fail, and direct invocation is not granted.
- [ ] Validate the execution role's least privilege on AWS, including log delivery.
- [ ] Agree an owning team, SLOs, and alert routing; then add alarms on `Errors`, `Throttles`, and `Url5xxCount`.
- [ ] Measure cold starts, memory, duration, and concurrency under expected load; agree abuse controls.
- [ ] Agree release/rollback requirements; use versions/aliases/canaries if reverting source and reapplying is insufficient.
- [ ] Review retention, payload privacy, regional requirements, and any KMS controls.
