# Every AWS API call goes to LocalStack on loopback, with dummy credentials and no real account.
provider "aws" {
  region                      = "eu-central-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam    = "http://127.0.0.1:4566"
    lambda = "http://127.0.0.1:4566"
    logs   = "http://127.0.0.1:4566"
    sts    = "http://127.0.0.1:4566"
  }

  default_tags {
    tags = { Project = "cinfra", Environment = "local", ManagedBy = "terraform" }
  }
}

locals {
  # services.json is the developer-owned catalog; each entry becomes one module instance.
  services = jsondecode(file("${path.module}/../../services.json"))
}

module "service" {
  source   = "../modules/lambda-service"
  for_each = local.services

  name         = "cinfra-local-${each.key}"
  source_dir   = "${path.module}/../../${each.value.source_dir}"
  architecture = var.architecture
  # Fields left out of the catalog become null, which the module replaces with its defaults.
  memory_mb          = try(each.value.memory_mb, null)
  timeout_seconds    = try(each.value.timeout_seconds, null)
  log_retention_days = try(each.value.log_retention_days, null)
  public_url         = true # Explicitly public for the loopback-only demo.
  # LocalStack-only: predictable http://<service>.lambda-url... URLs instead of random IDs.
  tags = { _custom_id_ = each.key }
}

output "service_urls" {
  value = { for name, service in module.service : name => service.url }
}

output "log_groups" {
  value = { for name, service in module.service : name => service.log_group_name }
}
