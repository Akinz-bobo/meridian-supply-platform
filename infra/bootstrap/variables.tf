# The bootstrap stack has its own variables: it belongs to the shared
# account and has no network. Values come from bootstrap.tfvars.

variable "project" {
  description = "Short name of the platform."
  type        = string
  default     = "meridian"
}

variable "environment" {
  description = "Environment name: dev, stg or prod."
  type        = string
}

variable "aws_region" {
  description = "Region the environment is deployed to."
  type        = string
}

variable "aws_account_id" {
  description = "Account the environment belongs to. Applying with credentials for any other account fails."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "aws_endpoint_url" {
  description = "Endpoint of a local AWS emulator. Leave null to target real AWS."
  type        = string
  default     = null
}
