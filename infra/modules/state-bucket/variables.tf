variable "name" {
  description = "Bucket name. Must be globally unique, so include the account id and region."
  type        = string
}

variable "tags" {
  description = "Tags for every resource in the module."
  type        = map(string)
}

variable "noncurrent_version_retention_days" {
  description = "How long a replaced state version is kept before it is deleted."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_retention_days >= 30
    error_message = "Keep old state versions for at least 30 days, so a bad apply found late can still be rolled back."
  }
}

variable "kms_deletion_window_days" {
  description = "Waiting period before the encryption key is destroyed after deletion is requested."
  type        = number
  default     = 30
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed while it still holds state. Only for throwaway environments."
  type        = bool
  default     = false
}
