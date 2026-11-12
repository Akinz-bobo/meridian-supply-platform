variable "name" {
  description = "Name of the bucket. Bucket names are global, so build it from the context module's prefix plus the account id and region."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "A bucket name is 3 to 63 characters of lower case letters, digits and hyphens. Dots are not used: they break TLS for virtual-hosted requests."
  }
}

variable "tags" {
  description = "Tags for the bucket. Take them from the context module."
  type        = map(string)
}

variable "data_classification" {
  description = "How sensitive the contents are: public, internal, confidential or restricted. Becomes the DataClassification tag."
  type        = string

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be public, internal, confidential or restricted. The levels are defined in docs/architecture/data.md."
  }
}

variable "kms_key_arn" {
  description = "ARN of the key that encrypts the bucket. Pass the data key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "Give the ARN of a KMS key. A bucket is not created without a customer managed key."
  }
}

variable "noncurrent_version_retention_days" {
  description = "How long a replaced or deleted version of an object is kept before it is removed for good."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_retention_days >= 7
    error_message = "Keep old versions for at least 7 days. They are what makes an overwrite or a deletion recoverable."
  }
}

variable "expiration_days" {
  description = "Delete objects this many days after they are created. With null, objects are kept until something deletes them."
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days == null ? true : var.expiration_days >= 1
    error_message = "expiration_days must be at least 1, or null to keep objects indefinitely."
  }
}

variable "transitions" {
  description = "Moves to cheaper storage as objects age, in order. Each entry is a number of days after creation and a storage class."
  type = list(object({
    days          = number
    storage_class = string
  }))
  default = []

  validation {
    condition = alltrue([
      for transition in var.transitions :
      contains(["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], transition.storage_class)
    ])
    error_message = "storage_class must be one of STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER_IR, GLACIER or DEEP_ARCHIVE."
  }

  validation {
    condition = alltrue([
      for transition in var.transitions :
      transition.days >= 30 || !contains(["STANDARD_IA", "ONEZONE_IA"], transition.storage_class)
    ])
    error_message = "S3 does not move an object to an infrequent access class before it is 30 days old."
  }

  validation {
    condition     = length(var.transitions) == length(distinct([for transition in var.transitions : transition.days]))
    error_message = "Each transition needs a different number of days."
  }
}

variable "eventbridge_notifications" {
  description = "Send an event to EventBridge for every object created, deleted or restored. Rules on the bus then decide who hears about it."
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Let Terraform delete the bucket while it still contains objects. Leave off anywhere the data matters."
  type        = bool
  default     = false
}
