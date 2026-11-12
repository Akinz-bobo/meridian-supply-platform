variable "name" {
  description = "Name of the cluster. Build it from the context module's prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name))
    error_message = "A cluster name starts with a letter and uses lower case letters, digits and single hyphens."
  }
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "exec_log_group_name" {
  description = "Name of the log group that records shell sessions in containers, a path under /<project>/<environment>/."
  type        = string

  validation {
    condition     = startswith(var.exec_log_group_name, "/")
    error_message = "Log group names in this platform are paths and start with a slash."
  }
}

variable "logs_kms_key_arn" {
  description = "ARN of the key that encrypts shell sessions and their log group. Pass the logs key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.logs_kms_key_arn))
    error_message = "Give the ARN of a KMS key."
  }
}

variable "log_retention_days" {
  description = "How long records of shell sessions are kept."
  type        = number
  default     = 365

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731], var.log_retention_days)
    error_message = "Retention must be a value CloudWatch accepts and at least 30 days: 30, 60, 90, 120, 150, 180, 365, 400, 545 or 731."
  }
}
