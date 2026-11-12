variable "path" {
  description = "Path the service owns, for example /meridian/prod/catalog. Take it from the context module's ssm_path."
  type        = string

  validation {
    condition     = can(regex("^/[a-z0-9-]+/[a-z0-9-]+/[a-z0-9-]+$", var.path))
    error_message = "The path is /<project>/<environment>/<service> with no trailing slash, for example /meridian/prod/catalog. Anything shorter would cover more than one service."
  }
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "account_id" {
  description = "Account the configuration is stored in. Used to name resources exactly in the read policy."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "kms_key_arn" {
  description = "ARN of the key that encrypts the secrets. Pass the secrets key."
  type        = string
}

variable "kms_key_alias" {
  description = "Alias of the same key, including the alias/ prefix. The read policy grants decryption by alias, which is known at plan time."
  type        = string

  validation {
    condition     = startswith(var.kms_key_alias, "alias/")
    error_message = "Give the alias with its prefix, for example alias/meridian-prod-secrets."
  }
}

variable "parameters" {
  description = "Plain configuration values, keyed by name. Stored at <path>/config/<key>. Never put a secret here: these values are stored unencrypted and appear in Terraform state."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for key in keys(var.parameters) : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", key))])
    error_message = "Parameter names are lower case words separated by hyphens, for example log-level."
  }

  validation {
    condition     = alltrue([for key in keys(var.parameters) : !can(regex("password|secret|token|api-key|private-key|credential", key))])
    error_message = "A parameter name suggests a secret. Secrets belong in the secrets input, where they are encrypted and kept out of state."
  }
}

variable "secrets" {
  description = <<-EOT
    Secrets the service owns, keyed by name. Stored at <path>/secrets/<name>.

    generate: create a random value. Without it the secret is created empty and its value is set outside Terraform.
      version: raise it to generate and store a new value.
    rotation: rotate automatically with the given Lambda function.
  EOT
  type = map(object({
    description = string
    generate = optional(object({
      length              = optional(number, 32)
      exclude_punctuation = optional(bool, true)
      version             = optional(number, 1)
    }))
    rotation = optional(object({
      lambda_arn               = string
      automatically_after_days = optional(number, 30)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for name in keys(var.secrets) : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))])
    error_message = "Secret names are lower case words separated by hyphens, for example database-credentials."
  }

  validation {
    condition     = alltrue([for secret in values(var.secrets) : secret.generate == null ? true : secret.generate.length >= 24])
    error_message = "A generated secret is at least 24 characters long."
  }

  validation {
    condition     = alltrue([for secret in values(var.secrets) : secret.rotation == null ? true : secret.rotation.automatically_after_days <= 90])
    error_message = "A rotated secret rotates at least every 90 days."
  }
}

variable "recovery_window_in_days" {
  description = "Days a deleted secret can still be restored."
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30
    error_message = "The recovery window must be between 7 and 30 days. Zero would delete a secret immediately and irreversibly."
  }
}
