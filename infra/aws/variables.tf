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

variable "architecture" {
  type        = string
  description = "Lambda CPU architecture; arm64 (Graviton) is cheaper than x86_64."
  default     = "arm64"
}

variable "name_prefix" {
  type        = string
  description = "Account-unique deployment prefix, including the environment."
  default     = "cinfra-dev"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,40}$", var.name_prefix))
    error_message = "Use 1–40 letters, numbers, underscores or hyphens."
  }
}

variable "public_urls" {
  type        = bool
  description = "Danger: allows anyone on the internet to invoke both services and incur charges."
  default     = false
}
