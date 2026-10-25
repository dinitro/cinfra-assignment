# Deploying to AWS

> **Verification status:** this path was not applied to a real AWS account. Terraform validation and mocked-provider tests pass. The commands below are the intended workflow, not evidence of a completed AWS deployment.

The AWS deployment is separate from LocalStack. Use a short-lived provisioning identity, such as an AWS SSO profile. The account guard allows only the account ID in `terraform.tfvars`.

## Direct deployment

Prerequisites: the [local check tools](../README.md#run-locally), AWS CLI v2, and `curl` with `--aws-sigv4` support. Use the exact revision that passed checks; CI never deploys to AWS.

```bash
make check
cp infra/aws/terraform.tfvars.example infra/aws/terraform.tfvars
# Set aws_account_id and review region/name_prefix.
export AWS_PROFILE=sandbox
aws sts get-caller-identity

# Ensure this root is not pointed at LocalStack.
unset AWS_ENDPOINT_URL AWS_ENDPOINT_URL_IAM AWS_ENDPOINT_URL_LAMBDA

terraform -chdir=infra/aws init -lockfile=readonly
terraform -chdir=infra/aws plan -out=deploy.tfplan
terraform -chdir=infra/aws apply deploy.tfplan
terraform -chdir=infra/aws output -json service_urls
```

State is local by default and ignored by git. State and plans contain source code and account/resource identifiers; keep them in an access-controlled location and preserve state for subsequent updates and cleanup. Shared/CI deployments need a separately managed remote backend with locking and verified deployment permissions; that setup is outside this assignment.

## Invoke an IAM URL

AWS URLs use `AWS_IAM` unless `public_urls = true`. The caller needs both Lambda Function URL actions. Attach the generated JSON to the approved calling role or user, not to the Lambda execution role:

```bash
terraform -chdir=infra/aws output -raw caller_policy > /tmp/cinfra-caller-policy.json
aws iam put-role-policy \
  --role-name <approved-caller-role> \
  --policy-name cinfra-function-url \
  --policy-document file:///tmp/cinfra-caller-policy.json
```

Use an AWS CLI profile for that approved caller, not the provisioning identity, when signing the request. Replace `approved-caller` with your profile name; the region must match `infra/aws/terraform.tfvars`:

```bash
export AWS_PROFILE=approved-caller
export REGION=eu-central-1
# curl reads credentials from these environment variables, not AWS_PROFILE.
eval "$(aws configure export-credentials --profile "$AWS_PROFILE" --format env)"

LENGTH_URL=$(terraform -chdir=infra/aws output -json service_urls | \
  python3 -c 'import json,sys; print(json.load(sys.stdin)["length"])')
curl --aws-sigv4 "aws:amz:${REGION}:lambda" \
  --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
  -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
  -H 'Content-Type: text/plain; charset=utf-8' \
  --data-binary 'hello' "$LENGTH_URL"
```

This same-account identity policy also permits direct `lambda:InvokeFunction` for the approved caller. Enforcing URL-only invocation requires a resource-based policy for a known caller principal; that extra configuration is outside this assignment. Unsigned requests should be denied. Public URLs remove the signing requirement but expose the functions to unauthenticated traffic with no rate or spending cap.

## Cleanup

Switch back to the provisioning identity and review the destroy plan before removing the AWS stack:

```bash
# Remove the caller credentials exported for curl so AWS_PROFILE takes effect again.
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export AWS_PROFILE=sandbox
aws sts get-caller-identity
terraform -chdir=infra/aws plan -destroy
terraform -chdir=infra/aws destroy
```

Destroying the stack also deletes managed log groups and their contents; export any required evidence first. Renaming or removing a catalog key has the same destructive effect on that service. The manually attached caller policy is not managed by Terraform; remove it from the approved role when it is no longer needed.
