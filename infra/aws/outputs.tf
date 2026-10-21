output "service_urls" {
  value = { for name, service in module.service : name => service.url }
}

output "log_groups" {
  value = { for name, service in module.service : name => service.log_group_name }
}

# Calling an IAM-authenticated Function URL requires both actions below.
output "caller_policy" {
  description = "Attach to an approved same-account caller, not the Lambda execution role."
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "lambda:InvokeFunctionUrl"
        Resource  = [for service in module.service : service.function_arn]
        Condition = { StringEquals = { "lambda:FunctionUrlAuthType" = "AWS_IAM" } }
      },
      {
        Effect    = "Allow"
        Action    = "lambda:InvokeFunction"
        Resource  = [for service in module.service : service.function_arn]
        Condition = { Bool = { "lambda:InvokedViaFunctionUrl" = "true" } }
      }
    ]
  })
}
