# Shared by every layer of every environment through a symbolic link. Values
# come from the environment's env.tfvars.

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

variable "vpc_cidr" {
  description = "Address range of the environment's VPC, a /16 from the address plan."
  type        = string
}

variable "availability_zones" {
  description = "Availability zones the environment is spread across."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway between all zones. Cheaper and less resilient, so only dev sets it."
  type        = bool
  default     = false
}

variable "interface_endpoint_services" {
  description = "AWS services given an interface endpoint in the VPC. With null, the vpc-endpoints module's default set is used."
  type        = set(string)
  default     = null
}

variable "log_retention_days" {
  description = "How long operational logs, including VPC flow logs, are kept."
  type        = number
  default     = 90
}
