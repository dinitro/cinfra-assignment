# Uses your normal AWS credentials, but refuses to apply to any account except aws_account_id.
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = { Project = "cinfra", Deployment = var.name_prefix, ManagedBy = "terraform" }
  }
}

locals {
  # Same developer-owned catalog as the local root, so both deploy identical services.
  services = jsondecode(file("${path.module}/../../services.json"))
}

module "service" {
  source   = "../modules/lambda-service"
  for_each = local.services

  name         = "${var.name_prefix}-${each.key}"
  source_dir   = "${path.module}/../../${each.value.source_dir}"
  architecture = var.architecture
  # Fields left out of the catalog become null, which the module replaces with its defaults.
  memory_mb          = try(each.value.memory_mb, null)
  timeout_seconds    = try(each.value.timeout_seconds, null)
  log_retention_days = try(each.value.log_retention_days, null)
  public_url         = var.public_urls
}
