# Tests the AWS root's wiring against a mocked provider; nothing is deployed and no credentials are used.
mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-function" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-central-1:123456789012:log-group:/aws/lambda/test-function" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:eu-central-1:123456789012:function:test-function" }
  }
}

variables { aws_account_id = "123456789012" }

run "catalog_and_safe_defaults" {
  command = apply

  assert {
    condition = (
      toset(keys(output.service_urls)) == toset(keys(local.services)) &&
      alltrue([for name in ["length", "json-validator"] : contains(keys(output.service_urls), name)]) &&
      module.service["length"].function_name == "cinfra-dev-length"
    )
    error_message = "Deploy the entire catalog, including the two required services, with environment-specific names."
  }
  assert {
    condition     = !var.public_urls
    error_message = "Public access must be opt-in."
  }
  assert {
    condition     = jsondecode(output.caller_policy).Statement[0].Condition.StringEquals["lambda:FunctionUrlAuthType"] == "AWS_IAM" && jsondecode(output.caller_policy).Statement[1].Condition.Bool["lambda:InvokedViaFunctionUrl"] == "true"
    error_message = "The caller policy must grant both required actions only for IAM-authenticated URL invocation."
  }
}
