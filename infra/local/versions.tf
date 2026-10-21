terraform {
  required_version = ">= 1.16.6, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.69.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.8.1"
    }
  }
}
