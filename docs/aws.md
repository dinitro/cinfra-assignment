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

## Deploy via GitHub Actions (OIDC)

`infra/bootstrap` provisions what CI needs so it never holds a credential: a GitHub OIDC identity
provider, a deploy role AWS will only hand out to a workflow job that declares a specific GitHub
Environment, and the S3 bucket `infra/aws`'s state moves into (so repeated CI runs see what
earlier runs created, instead of starting from empty state and colliding with it). Apply it once,
by hand, with an admin identity in your sandbox account — nothing it creates can also be what
grants itself access:

```bash
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars
# Edit aws_account_id, and deploy_name_prefix if you changed infra/aws's name_prefix — they must match.
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap apply
terraform -chdir=infra/bootstrap output
```

Then, one-time setup in GitHub:

1. **Settings → Environments** — create an environment named `aws-sandbox` (matching
   `github_environment` above), add yourself as a required reviewer, and restrict deployment
   branches to `main`. This, not any secret, is the actual gate: the deploy role's trust policy
   only accepts tokens from a job running under this exact environment.
2. **Settings → Secrets and variables → Actions → Variables** — add `AWS_DEPLOY_ROLE_ARN` and
   `AWS_TF_STATE_BUCKET` from the bootstrap outputs above, plus `AWS_ACCOUNT_ID`, `AWS_REGION`
   (`eu-central-1`), `AWS_NAME_PREFIX` (`cinfra-dev`). These are repository **variables**, not
   secrets — none of them are credentials, so there's nothing in them worth hiding. The workflows
   in `.github/workflows/deploy-aws.yml` and `destroy-aws.yml` reference only `vars.*`, never
   `secrets.*`.

From here, pushing to `main` runs `deploy-aws.yml`, which pauses for your environment approval
before `terraform apply`. `destroy-aws.yml` is manual-only (`workflow_dispatch`) and pauses the
same way before `terraform destroy`.

If you've already applied `infra/aws` locally with local state, migrate it into the new backend
once:

```bash
cp infra/aws/backend.tf.example infra/aws/backend.tf
cp infra/aws/backend.hcl.example infra/aws/backend.hcl   # fill in the bucket name from bootstrap's output
terraform -chdir=infra/aws init -backend-config=backend.hcl -migrate-state
```

## Before production

- [ ] Confirm the account, environment, ownership, request-volume expectations, and cost budget.
- [x] Move state to a dedicated private, encrypted, versioned S3 bucket with native locking (`use_lockfile = true`), managed outside this stack — see [above](#deploy-via-github-actions-oidc); `infra/bootstrap` provisions it.
- [x] Deploy from CI through a protected environment using GitHub OIDC and a scoped, short-lived deployment role; no repository secrets, no unreviewed pull-request code — see [above](#deploy-via-github-actions-oidc).
- [ ] Verify signed approved callers succeed, unsigned/unapproved callers fail, and direct invocation is not granted.
- [ ] Validate the execution role's least privilege on AWS, including log delivery.
- [ ] Agree an owning team, SLOs, and alert routing; then add alarms on `Errors`, `Throttles`, and `Url5xxCount`.
- [ ] Measure cold starts, memory, duration, and concurrency under expected load; agree abuse controls.
- [ ] Agree release/rollback requirements; use versions/aliases/canaries if reverting source and reapplying is insufficient.
- [ ] Review retention, payload privacy, regional requirements, and any KMS controls.
