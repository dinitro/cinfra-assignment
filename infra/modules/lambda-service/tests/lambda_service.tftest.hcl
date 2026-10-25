# Tests this module against a mocked AWS provider: no credentials or LocalStack needed.
# The mocks supply ARNs, which the policies and role references need.
mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-function" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-central-1:123456789012:log-group:/aws/lambda/test-function" }
  }
}

variables {
  name       = "test-function"
  source_dir = "../../../functions/length"
}

run "private_by_default" {
  command = apply

  assert {
    condition     = aws_lambda_function_url.function.authorization_type == "AWS_IAM" && length(aws_lambda_permission.public_url) == 0 && length(aws_lambda_permission.public_invoke) == 0
    error_message = "Default deployments must require IAM and must not grant public invocation."
  }
  assert {
    condition     = jsondecode(aws_iam_role.execution.assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com"
    error_message = "Only the Lambda service should assume the execution role."
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.logs.policy).Statement[0].Action) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) && jsondecode(aws_iam_role_policy.logs.policy).Statement[0].Resource == "${aws_cloudwatch_log_group.function.arn}:*"
    error_message = "Runtime permissions must be limited to writing this function's pre-created log group."
  }
  assert {
    condition     = aws_lambda_function.function.architectures == tolist(["arm64"])
    error_message = "Default to arm64, the cheaper architecture on AWS."
  }
  assert {
    condition     = aws_cloudwatch_log_group.function.retention_in_days == 14 && aws_lambda_function.function.memory_size == 128 && aws_lambda_function.function.timeout == 5
    error_message = "The platform must supply bounded execution and log retention defaults."
  }
  assert {
    condition     = try(aws_lambda_function.function.tags["_custom_id_"], null) == null
    error_message = "The module must not add LocalStack-only tags; only the local root opts in."
  }
  assert {
    condition     = aws_lambda_function.function.source_code_hash == data.archive_file.code.output_base64sha256
    error_message = "Code changes must trigger deployment through the ZIP hash."
  }
}

run "public_access_is_url_only" {
  command = apply
  variables { public_url = true }

  assert {
    condition     = aws_lambda_function_url.function.authorization_type == "NONE" && aws_lambda_permission.public_url[0].action == "lambda:InvokeFunctionUrl" && aws_lambda_permission.public_url[0].function_url_auth_type == "NONE"
    error_message = "Public access must be explicitly enabled for the URL."
  }
  assert {
    condition     = aws_lambda_permission.public_invoke[0].action == "lambda:InvokeFunction" && aws_lambda_permission.public_invoke[0].invoked_via_function_url
    error_message = "The second required permission must not allow anonymous direct invocation."
  }
}

run "reject_unbounded_timeout" {
  command = plan
  variables { timeout_seconds = 900 }
  expect_failures = [var.timeout_seconds]
}

run "reject_missing_entrypoint" {
  command = plan
  variables { source_dir = "../../../functions/does-not-exist" }
  expect_failures = [var.source_dir]
}
