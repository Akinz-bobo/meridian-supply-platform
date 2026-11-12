variable "name" {
  description = "Name of the repository, one per service. Build it from the context module's prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 256
    error_message = "A repository name starts with a letter and uses lower case letters, digits and single hyphens."
  }
}

variable "tags" {
  description = "Tags for the repository. Take them from the context module."
  type        = map(string)
}

variable "account_id" {
  description = "Account the repository is in. Used to name it exactly in the access policies."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "kms_key_arn" {
  description = "ARN of the key that encrypts images at rest. Pass the data key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "Give the ARN of a KMS key. A repository is not created without a customer managed key."
  }
}

variable "keep_tagged_images" {
  description = "How many images to keep. Older ones are removed. It must be enough to roll back as far as you might need to."
  type        = number
  default     = 30

  validation {
    condition     = var.keep_tagged_images >= 5
    error_message = "Keep at least 5 images, or a rollback may find its image gone."
  }
}

variable "untagged_retention_days" {
  description = "Days an image with no tag is kept. Untagged images are leftovers of interrupted pushes."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_retention_days >= 1
    error_message = "untagged_retention_days must be at least 1."
  }
}

variable "force_delete" {
  description = "Let Terraform delete the repository while it still holds images. Turn on only in an environment whose data is disposable."
  type        = bool
  default     = false
}
