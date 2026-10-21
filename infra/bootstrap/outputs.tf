output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github_actions.arn
}

output "deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN GitHub Actions repository variable."
  value       = aws_iam_role.deploy.arn
}

output "state_bucket_name" {
  description = "Set as the AWS_TF_STATE_BUCKET GitHub Actions repository variable, and used in infra/aws/backend.hcl."
  value       = aws_s3_bucket.state.bucket
}
