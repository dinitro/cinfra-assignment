output "url" {
  value       = aws_lambda_function_url.function.function_url
  description = "POST UTF-8 text here; IAM-authenticated unless public access was explicitly enabled."
}

output "function_name" {
  value = aws_lambda_function.function.function_name
}

output "function_arn" {
  value = aws_lambda_function.function.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.function.name
}
