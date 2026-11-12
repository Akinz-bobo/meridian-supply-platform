variable "name" {
  description = "Name of the stream. Build it from the context module's prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 128
    error_message = "A stream name starts with a letter, uses lower case letters, digits and single hyphens, and is at most 128 characters."
  }
}

variable "tags" {
  description = "Tags for the stream. Take them from the context module."
  type        = map(string)
}

variable "account_id" {
  description = "Account the stream is in. Used to name it exactly in the access policies."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "data_classification" {
  description = "How sensitive the records are: public, internal, confidential or restricted. Becomes the DataClassification tag."
  type        = string

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be public, internal, confidential or restricted. The levels are defined in docs/architecture/data.md."
  }
}

variable "kms_key_arn" {
  description = "ARN of the key that encrypts records in the stream. Pass the messaging key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "Give the ARN of a KMS key. A stream is not created without a customer managed key."
  }
}

variable "shard_count" {
  description = "Fixed number of shards. With null the stream is on demand and scales its own shards, which suits traffic that arrives in bursts."
  type        = number
  default     = null

  validation {
    condition     = var.shard_count == null ? true : var.shard_count >= 1 && var.shard_count <= 200
    error_message = "shard_count must be between 1 and 200, or null for an on-demand stream."
  }
}

variable "retention_hours" {
  description = "How long records can be read, and read again. A consumer that is down for longer than this loses records."
  type        = number
  default     = 48

  validation {
    condition     = var.retention_hours >= 24 && var.retention_hours <= 8760
    error_message = "retention_hours must be between 24 and 8760, which is one year."
  }
}
