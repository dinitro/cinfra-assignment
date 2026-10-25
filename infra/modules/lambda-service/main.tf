locals {
  # Every ZIP also gets platform_http.py, so handlers can import the shared HTTP adapter.
  # Standard-library Python sources only; dependencies or non-Python assets need a build step.
  sources = merge(
    { for name in fileset(var.source_dir, "**/*.py") : name => file("${var.source_dir}/${name}") },
    { "platform_http.py" = file("${path.module}/runtime/platform_http.py") }
  )
}

data "archive_file" "code" {
  # Another source revision must not overwrite the artifact referenced by a saved plan.
  type             = "zip"
  output_path      = "${path.root}/.terraform/${var.name}-${sha256(jsonencode(local.sources))}.zip"
  output_file_mode = "0644"
  dynamic "source" {
    for_each = local.sources
    content {
      filename = source.key
      content  = source.value
    }
  }
}

# Created up front so retention applies and the role can be scoped to this one log group.
resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
}

# One role per function, assumable only by the Lambda service.
resource "aws_iam_role" "execution" {
  name = var.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# The function's only permission: write to its own log group.
resource "aws_iam_role_policy" "logs" {
  name = "write-own-logs"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.function.arn}:*"
    }]
  })
}

resource "aws_lambda_function" "function" {
  function_name    = var.name
  role             = aws_iam_role.execution.arn
  runtime          = "python3.14"
  architectures    = [var.architecture]
  handler          = "handler.handler"
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  memory_size      = var.memory_mb
  timeout          = var.timeout_seconds
  tags             = var.tags

  # Make sure the role can write logs before the first invocation.
  depends_on = [aws_iam_role_policy.logs]
}

# Each function gets its own HTTPS endpoint. AWS_IAM means callers must sign requests (SigV4).
resource "aws_lambda_function_url" "function" {
  function_name      = aws_lambda_function.function.function_name
  authorization_type = var.public_url ? "NONE" : "AWS_IAM"
}

# A public URL needs both permissions below. The second only allows invocation through the URL,
# so anonymous callers still cannot call the Lambda Invoke API directly.
resource "aws_lambda_permission" "public_url" {
  count                  = var.public_url ? 1 : 0
  statement_id           = "AllowPublicFunctionURL"
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_name          = aws_lambda_function_url.function.function_name
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "public_invoke" {
  count                    = var.public_url ? 1 : 0
  statement_id             = "AllowPublicInvokeOnlyViaURL"
  action                   = "lambda:InvokeFunction"
  principal                = "*"
  function_name            = aws_lambda_function_url.function.function_name
  invoked_via_function_url = true
}

