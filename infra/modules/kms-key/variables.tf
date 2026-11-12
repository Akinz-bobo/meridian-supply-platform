variable "name" {
  description = "Name of the key, used as its alias: alias/<name>. Take it from the context module's prefix."
  type        = string

  validation {
    condition     = !startswith(var.name, "alias/")
    error_message = "Give the name without the alias/ prefix. The module adds it."
  }
}

variable "tags" {
  description = "Tags for the key. Take them from the context module."
  type        = map(string)
}

variable "description" {
  description = "What the key protects, in one sentence. Shown in the console and in audit records."
  type        = string

  validation {
    condition     = length(var.description) >= 10
    error_message = "Describe what the key protects in at least a few words."
  }
}

variable "account_id" {
  description = "Account that owns the key. Its IAM policies control who may use it."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "service_principals" {
  description = "AWS services allowed to use the key for this account, for example logs.eu-west-1.amazonaws.com."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for principal in var.service_principals : endswith(principal, ".amazonaws.com")])
    error_message = "A service principal ends in .amazonaws.com, for example sns.amazonaws.com."
  }
}

variable "rotation_period_in_days" {
  description = "How often AWS replaces the key material, in days. With null, AWS uses its default of 365. Old material is kept, so existing data stays readable."
  type        = number
  default     = null

  validation {
    condition     = var.rotation_period_in_days == null ? true : var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 365
    error_message = "Rotate at least once a year and no more often than every 90 days."
  }
}

variable "deletion_window_in_days" {
  description = "Days between scheduling the key for deletion and its deletion. Deletion makes everything encrypted with the key unreadable, and this is the time to notice."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 14 && var.deletion_window_in_days <= 30
    error_message = "The deletion window must be between 14 and 30 days. AWS allows 7, and the encryption standard does not."
  }
}
