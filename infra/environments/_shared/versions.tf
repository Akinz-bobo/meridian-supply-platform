# Shared by every layer of every environment through a symbolic link, so that
# all of them are pinned to the same Terraform and provider versions.

terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
