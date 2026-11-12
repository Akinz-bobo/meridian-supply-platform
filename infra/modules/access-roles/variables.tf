variable "name" {
  description = "Prefix of the roles: <name>-deploy, <name>-operator and <name>-audit. Take it from the context module's prefix."
  type        = string
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "account_id" {
  description = "Account of the environment the roles give access to."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "region" {
  description = "Region the environment is deployed to. The pipeline can manage resources in this region only."
  type        = string
}

variable "identity_account_id" {
  description = "Account where people sign in. Its principals may assume the operator and audit roles, with multi-factor authentication."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.identity_account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "deploy_subjects" {
  description = "GitHub OpenID Connect subjects allowed to assume the deploy role, for example repo:owner/repository:environment:production."
  type        = set(string)

  validation {
    condition     = length(var.deploy_subjects) > 0
    error_message = "Name at least one subject, or nothing can deploy."
  }

  validation {
    condition     = alltrue([for subject in var.deploy_subjects : can(regex("^repo:[^/*]+/[^/*:]+:(environment:[^*]+|ref:refs/heads/[^*]+)$", subject))])
    error_message = "Each subject must name one repository and one environment or branch, with no wildcard: repo:<owner>/<repository>:environment:<name> or repo:<owner>/<repository>:ref:refs/heads/<branch>. A wildcard would let pull requests from forks assume the role."
  }
}

variable "deploy_services" {
  description = "AWS services the pipeline manages, by IAM prefix. IAM is handled separately and may not be listed."
  type        = set(string)
  default = [
    "apigateway",
    "athena",
    "cloudfront",
    "cloudwatch",
    "dynamodb",
    "ec2",
    "ecr",
    "ecs",
    "eks",
    "elasticache",
    "elasticloadbalancing",
    "events",
    "firehose",
    "glue",
    "kinesis",
    "kms",
    "lambda",
    "logs",
    "rds",
    "s3",
    "scheduler",
    "secretsmanager",
    "sns",
    "sqs",
    "ssm",
    "states",
  ]

  validation {
    condition     = length(setintersection(var.deploy_services, ["iam", "organizations", "account", "sts", "*"])) == 0
    error_message = "iam, organizations, account, sts and * may not be listed. Identity is granted by its own narrower statements."
  }
}

variable "resource_prefix" {
  description = "Prefix that every named resource of the environment starts with, including the trailing hyphen, for example meridian-prod-."
  type        = string

  validation {
    condition     = endswith(var.resource_prefix, "-")
    error_message = "The resource prefix ends with a hyphen, for example meridian-prod-."
  }
}

variable "path_prefix" {
  description = "Path that every log group of the environment lives under, including the trailing slash, for example /meridian/prod/."
  type        = string

  validation {
    condition     = startswith(var.path_prefix, "/") && endswith(var.path_prefix, "/")
    error_message = "The path prefix starts and ends with a slash, for example /meridian/prod/."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of the workload permission boundary. The pipeline can create a role only if the role carries it."
  type        = string
}

variable "logs_key_alias" {
  description = "Alias of the key that encrypts log groups, including the alias/ prefix. Operators may decrypt with it, and with no other key."
  type        = string

  validation {
    condition     = startswith(var.logs_key_alias, "alias/")
    error_message = "Give the alias with its prefix, for example alias/meridian-prod-logs."
  }
}

variable "state_bucket_name" {
  description = "Name of the bucket that holds Terraform state."
  type        = string
}

variable "state_key_prefix" {
  description = "Prefix of this environment's state in the bucket, without slashes, for example production. The pipeline can read and write only under it."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.state_key_prefix))
    error_message = "The state key prefix is the environment's directory name: lower case letters, digits and hyphens."
  }
}

variable "state_account_id" {
  description = "Account that owns the state bucket and its key."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.state_account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "allow_key_deletion" {
  description = "Let the pipeline disable encryption keys and schedule them for deletion. Only for an environment whose data is disposable and which the pipeline tears down."
  type        = bool
  default     = false
}

variable "service_boundary_arns" {
  description = "Further boundaries the pipeline may create roles with, for AWS service roles whose work falls outside the workload boundary. Each must be an AWS managed policy written for one service, such as the backup service's own policy."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.service_boundary_arns : can(regex("^arn:aws[a-z-]*:iam::aws:policy/", arn))])
    error_message = "A service boundary must be an AWS managed policy, with an ARN starting arn:aws:iam::aws:policy/. A customer managed policy could be changed to allow anything."
  }

  validation {
    condition     = alltrue([for arn in var.service_boundary_arns : !endswith(arn, "/AdministratorAccess") && !endswith(arn, "/PowerUserAccess") && !endswith(arn, "FullAccess")])
    error_message = "AdministratorAccess, PowerUserAccess and the FullAccess policies may not be used as a boundary."
  }
}
