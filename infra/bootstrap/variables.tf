variable "aws_account_id" {
  type        = string
  description = "Expected real AWS account. The provider refuses to deploy into another account."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id)) && var.aws_account_id != "000000000000"
    error_message = "Supply your real 12-digit AWS account ID, not LocalStack's account ID."
  }
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "github_repo" {
  type        = string
  description = "GitHub repo allowed to assume the deploy role, as owner/repo."
  default     = "dinitro/cinfra-assignment"
  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "Use the owner/repo form, e.g. dinitro/cinfra-assignment."
  }
}

variable "github_environment" {
  type        = string
  description = "GitHub Environment name the deploy/destroy workflow jobs must declare. Must match the Environment configured in the repo's settings (with required reviewers and a branch restriction) and the name used by the workflow files."
  default     = "aws-sandbox"
}

variable "deploy_name_prefix" {
  type        = string
  description = "Must equal infra/aws's name_prefix. The deploy role's permissions are scoped to resources named <deploy_name_prefix>-*; nothing enforces the match automatically."
  default     = "cinfra-dev"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,40}$", var.deploy_name_prefix))
    error_message = "Use 1–40 letters, numbers, underscores or hyphens."
  }
}
