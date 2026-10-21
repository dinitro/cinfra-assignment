# Applied once by hand with an admin identity (see docs/aws.md). Nothing here can be created by
# the CI it enables: CI's own AWS access and infra/aws's remote state both depend on this root.
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = { Project = "cinfra", Deployment = "bootstrap", ManagedBy = "terraform" }
  }
}

# GitHub's own OIDC signing certificate; avoids hardcoding a thumbprint that could rotate.
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
}

# Holds infra/aws's Terraform state so repeated CI runs see the resources earlier runs created.
# Globally-unique name derived from the account ID, so no random suffix is needed.
resource "aws_s3_bucket" "state" {
  bucket = "${var.deploy_name_prefix}-tfstate-${var.aws_account_id}"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Assumable only by workflow jobs that declare the named GitHub Environment, which is what the
# environment's required-reviewer/branch-restriction rules actually protect. Nothing here is a
# secret; the trust is this condition plus the signed OIDC token.
resource "aws_iam_role" "deploy" {
  name = "${var.deploy_name_prefix}-github-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:environment:${var.github_environment}"
        }
      }
    }]
  })
}

# Scoped to exactly what infra/modules/lambda-service and infra/aws create, named
# <deploy_name_prefix>-*, plus access to this root's own state object.
resource "aws_iam_role_policy" "deploy" {
  name = "deploy-infra-aws"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaFunctions"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:ListVersionsByFunction",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:ListTags",
          "lambda:CreateFunctionUrlConfig",
          "lambda:GetFunctionUrlConfig",
          "lambda:UpdateFunctionUrlConfig",
          "lambda:DeleteFunctionUrlConfig",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy",
        ]
        Resource = "arn:aws:lambda:${var.region}:${var.aws_account_id}:function:${var.deploy_name_prefix}-*"
      },
      {
        Sid    = "ExecutionRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:GetRole",
          "iam:DeleteRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRolePolicies",
        ]
        Resource = "arn:aws:iam::${var.aws_account_id}:role/${var.deploy_name_prefix}-*"
      },
      {
        Sid       = "PassExecutionRolesToLambdaOnly"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = "arn:aws:iam::${var.aws_account_id}:role/${var.deploy_name_prefix}-*"
        Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } }
      },
      {
        Sid    = "LogGroups"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DescribeLogGroups",
          "logs:TagResource",
        ]
        Resource = "arn:aws:logs:${var.region}:${var.aws_account_id}:log-group:/aws/lambda/${var.deploy_name_prefix}-*"
      },
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.state.arn
      },
      {
        Sid      = "StateObject"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.state.arn}/aws/terraform.tfstate"
      },
      {
        Sid      = "WhoAmI"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
    ]
  })
}
