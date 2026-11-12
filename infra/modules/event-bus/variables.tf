variable "name" {
  description = "Name of the bus, and the prefix of its archive, rule and log group. Build it from the context module's prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 48
    error_message = "The name starts with a letter, uses lower case letters, digits and single hyphens, and is at most 48 characters, which is the limit for an archive."
  }
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "description" {
  description = "What travels on the bus, in one sentence."
  type        = string
  default     = "Business events between the platform's services."
}

variable "account_id" {
  description = "Account the bus is in. Nothing outside it can publish."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "source_prefix" {
  description = "First part of every event's source. A publisher called procurement publishes as <source_prefix>.procurement."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*$", var.source_prefix))
    error_message = "The source prefix is one lower case word, for example meridian."
  }
}

variable "publishers" {
  description = "Services that publish to the bus, by the name used in their source. Each gets a publish policy limited to that source."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for publisher in var.publishers : can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", publisher))])
    error_message = "Publisher names are lower case words separated by hyphens, for example erp-gateway."
  }
}

variable "kms_key_arn" {
  description = "ARN of the key that encrypts events on the bus and in the archive. Pass the messaging key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "Give the ARN of a KMS key. A bus is not created without a customer managed key."
  }
}

variable "logs_kms_key_arn" {
  description = "ARN of the key that encrypts the event log group. Pass the logs key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.logs_kms_key_arn))
    error_message = "Give the ARN of a KMS key."
  }
}

variable "archive_retention_days" {
  description = "How long events are kept for replay."
  type        = number
  default     = 90

  validation {
    condition     = var.archive_retention_days >= 7
    error_message = "Keep events for at least 7 days. Zero would keep them for ever, which nobody has decided to pay for."
  }
}

variable "log_retention_days" {
  description = "How long the readable log of events is kept."
  type        = number
  default     = 30

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731], var.log_retention_days)
    error_message = "Retention must be a value CloudWatch accepts and at least 30 days: 30, 60, 90, 120, 150, 180, 365, 400, 545 or 731."
  }
}

variable "manage_log_resource_policy" {
  description = "Create the CloudWatch Logs resource policy that lets EventBridge write to the event log. Turn off when the account already has a policy covering /aws/events/ log groups, or where the target cannot manage one."
  type        = bool
  default     = true
}
