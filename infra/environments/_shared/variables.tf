# tflint-ignore-file: terraform_unused_declarations
#
# Shared by every layer of every environment through a symbolic link. Values
# come from the environment's env.tfvars.
#
# Every layer declares every variable, because they all read the same
# env.tfvars and Terraform warns about a value with no declaration. A layer
# does not use all of them, so the unused declaration rule is switched off
# for this file only, by the annotation on the first line, which is where
# the linter requires it. Unused locals and data sources are still reported.

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

variable "identity_account_id" {
  description = "Account where people sign in before assuming a role in an environment."
  type        = string
  default     = "444444444444"
}

variable "github_repository" {
  description = "Repository whose workflows may deploy, as owner/name."
  type        = string
  default     = "Akinz-bobo/meridian-supply-platform"
}

variable "github_environment" {
  description = "GitHub deployment environment whose jobs may assume this environment's deploy role."
  type        = string
}

variable "state_bucket_name" {
  description = "Bucket that holds Terraform state. The same value as in backend.hcl, which Terraform cannot read from configuration."
  type        = string
  default     = "meridian-shared-tfstate-444444444444-eu-west-1"
}

variable "state_account_id" {
  description = "Account that owns the state bucket."
  type        = string
  default     = "444444444444"
}

variable "state_key_prefix" {
  description = "Prefix of this environment's state in the bucket: the name of the environment's directory."
  type        = string
}

variable "disposable" {
  description = "The environment holds no data worth keeping and may be torn down by the pipeline. Relaxes protections that exist to prevent data loss."
  type        = bool
  default     = false
}

variable "database_instance_class" {
  description = "Size of the PostgreSQL instances."
  type        = string
  default     = "db.t4g.medium"
}

variable "database_multi_az" {
  description = "Give each database a standby in a second zone."
  type        = bool
  default     = true
}

variable "database_backup_retention_days" {
  description = "Days of automated database backups."
  type        = number
  default     = 14
}

variable "cache_node_type" {
  description = "Size of each cache node."
  type        = string
  default     = "cache.t4g.small"
}

variable "cache_replicas" {
  description = "Cache replicas in other zones. Zero means no automatic failover."
  type        = number
  default     = 1
}

variable "alarm_subscriptions" {
  description = "Where alarms are delivered in this environment, keyed by a short name. Each entry has a protocol (email, https, sqs, lambda, sms or firehose) and an endpoint. Empty means alarms reach nobody."
  type = map(object({
    protocol = string
    endpoint = string
  }))
  default = {}
}

variable "domain_name" {
  description = "Host name the environment is served under. The load balancer's certificate is issued for it."
  type        = string
}
