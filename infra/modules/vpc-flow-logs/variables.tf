variable "name" {
  description = "Prefix for the role and the flow log. Take it from the context module's prefix."
  type        = string
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "vpc_id" {
  description = "Identifier of the VPC to record."
  type        = string
}

variable "account_id" {
  description = "Account the VPC is in. The delivery role can be assumed only on behalf of this account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "log_group_name" {
  description = "Name of the log group, a path under /<project>/<environment>/."
  type        = string

  validation {
    condition     = startswith(var.log_group_name, "/")
    error_message = "Log group names in this platform are paths and start with a slash."
  }
}

variable "retention_in_days" {
  description = "How long flow logs are kept."
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731], var.retention_in_days)
    error_message = "Retention must be a value CloudWatch accepts and at least 30 days: 30, 60, 90, 120, 150, 180, 365, 400, 545 or 731. Shorter than 30 days is too little to investigate an incident found late."
  }
}

variable "traffic_type" {
  description = "Which traffic to record: ALL, ACCEPT or REJECT."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.traffic_type)
    error_message = "traffic_type must be ALL, ACCEPT or REJECT."
  }
}

variable "max_aggregation_interval" {
  description = "Seconds over which a flow is aggregated into one record: 60 or 600."
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 600], var.max_aggregation_interval)
    error_message = "max_aggregation_interval must be 60 or 600."
  }
}

variable "kms_key_arn" {
  description = "Customer managed key that encrypts the log group. With null, CloudWatch encrypts with a key it owns."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "ARN of the environment's permission boundary, set on the delivery role."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:policy/.+", var.permissions_boundary_arn))
    error_message = "Give the ARN of an IAM policy, for example arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary."
  }
}
