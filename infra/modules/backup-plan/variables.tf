variable "name" {
  description = "Name of the vault and the plan, and the prefix of the service role. Build it from the context module's prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 50
    error_message = "The name starts with a letter, uses lower case letters, digits and single hyphens, and is at most 50 characters."
  }
}

variable "tags" {
  description = "Tags for every resource in the module, and for the recovery points. Take them from the context module."
  type        = map(string)
}

variable "account_id" {
  description = "Account the vault is in. The backup service may assume the role only on behalf of this account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "kms_key_arn" {
  description = "ARN of the key that encrypts recovery points in the vault. Use a key of the vault's own, so that access to backups is separate from access to the originals."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "Give the ARN of a KMS key. A vault is not created without a customer managed key."
  }
}

variable "rules" {
  description = "Backup rules, keyed by name. schedule is a cron expression in UTC, in the form AWS uses: cron(minute hour day-of-month month day-of-week year)."
  type = map(object({
    schedule       = string
    retention_days = number
  }))
  default = {
    daily = {
      schedule       = "cron(0 2 * * ? *)"
      retention_days = 35
    }
  }

  validation {
    condition     = length(var.rules) > 0
    error_message = "A backup plan needs at least one rule."
  }

  validation {
    condition     = alltrue([for rule in values(var.rules) : can(regex("^cron\\(.+\\)$", rule.schedule))])
    error_message = "schedule must be a cron expression, for example cron(0 2 * * ? *)."
  }

  validation {
    condition     = alltrue([for rule in values(var.rules) : rule.retention_days >= 7])
    error_message = "Keep backups for at least 7 days. A problem found on a Monday must still be recoverable from before the weekend."
  }
}

variable "selection_tag" {
  description = "Tag that opts a resource in to this plan. A resource with this key and value is backed up, and nothing else is."
  type = object({
    key   = string
    value = string
  })
  default = {
    key   = "Backup"
    value = "daily"
  }
}

variable "lock_min_retention_days" {
  description = "Lock the vault so that no recovery point can be given a shorter life than this. With null the vault is not locked, which suits a disposable environment."
  type        = number
  default     = 7

  validation {
    condition     = var.lock_min_retention_days == null ? true : var.lock_min_retention_days >= 1
    error_message = "lock_min_retention_days must be at least 1, or null for no lock."
  }

  validation {
    condition     = var.lock_min_retention_days == null ? true : alltrue([for rule in values(var.rules) : rule.retention_days >= var.lock_min_retention_days])
    error_message = "Every rule must keep backups at least as long as the lock's minimum, or its backups would be refused by the vault."
  }
}

variable "force_destroy" {
  description = "Let Terraform delete the vault while it still holds recovery points. Turn on only in an environment whose data is disposable."
  type        = bool
  default     = false
}
