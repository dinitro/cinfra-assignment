# Tests the bootstrap root's wiring against mocked providers; nothing is deployed and no
# credentials are used.
mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/cinfra-dev-github-deploy" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn    = "arn:aws:s3:::cinfra-dev-tfstate-123456789012"
      bucket = "cinfra-dev-tfstate-123456789012"
    }
  }
}

mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [{ sha1_fingerprint = "6938fd4d98bab03faadb97b34396831e3780aea1" }]
    }
  }
}

variables { aws_account_id = "123456789012" }

run "trust_policy_scoped_to_repo_and_environment" {
  command = apply

  assert {
    condition = (
      jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:${var.github_repo}:environment:${var.github_environment}"
    )
    error_message = "The deploy role must only be assumable by a workflow job declaring the configured GitHub Environment, not the whole repo or any branch."
  }
}

run "pass_role_constrained_to_lambda" {
  command = apply

  assert {
    condition = (
      [for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s if s.Sid == "PassExecutionRolesToLambdaOnly"][0].Condition.StringEquals["iam:PassedToService"] == "lambda.amazonaws.com"
    )
    error_message = "iam:PassRole must stay constrained to roles only being passed to the Lambda service."
  }
}

run "state_bucket_is_private" {
  command = apply

  assert {
    condition     = aws_s3_bucket_public_access_block.state.block_public_acls && aws_s3_bucket_public_access_block.state.block_public_policy
    error_message = "The Terraform state bucket must never be publicly accessible."
  }
}
