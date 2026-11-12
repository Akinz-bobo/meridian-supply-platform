variable "name" {
  description = "Name of the table. Build it from the context module's prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name)) && length(var.name) >= 3 && length(var.name) <= 255
    error_message = "A table name is lower case letters, digits and single hyphens, between 3 and 255 characters."
  }
}

variable "tags" {
  description = "Tags for the table. Take them from the context module."
  type        = map(string)
}

variable "account_id" {
  description = "Account the table is in. Used to name the table exactly in the access policies."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
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
  description = "ARN of the key that encrypts the table. Pass the data key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "Give the ARN of a KMS key. A table is not created without a customer managed key."
  }
}

variable "hash_key" {
  description = "Name of the partition key attribute."
  type        = string
}

variable "range_key" {
  description = "Name of the sort key attribute. With null the table has a partition key only."
  type        = string
  default     = null
}

variable "attributes" {
  description = "Type of every attribute used in a key of the table or of an index: S (string), N (number) or B (binary). Attributes that are not part of a key are not declared."
  type        = map(string)

  validation {
    condition     = alltrue([for type in values(var.attributes) : contains(["S", "N", "B"], type)])
    error_message = "An attribute type is S, N or B."
  }

  validation {
    condition = length(setsubtract(
      compact(concat([var.hash_key, var.range_key], flatten([for index in var.global_secondary_indexes : [index.hash_key, index.range_key]]))),
      keys(var.attributes),
    )) == 0
    error_message = "Every key of the table and of its indexes must have its type declared in attributes."
  }

  validation {
    condition = length(setsubtract(
      keys(var.attributes),
      compact(concat([var.hash_key, var.range_key], flatten([for index in var.global_secondary_indexes : [index.hash_key, index.range_key]]))),
    )) == 0
    error_message = "attributes lists an attribute that is not part of any key. DynamoDB rejects that: only key attributes are declared."
  }
}

variable "global_secondary_indexes" {
  description = "Indexes that give the table further access patterns. projection_type is ALL, KEYS_ONLY or INCLUDE, and INCLUDE needs non_key_attributes."
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    projection_type    = optional(string, "ALL")
    non_key_attributes = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = alltrue([for index in var.global_secondary_indexes : contains(["ALL", "KEYS_ONLY", "INCLUDE"], index.projection_type)])
    error_message = "projection_type must be ALL, KEYS_ONLY or INCLUDE."
  }

  validation {
    condition     = alltrue([for index in var.global_secondary_indexes : index.projection_type != "INCLUDE" || length(index.non_key_attributes) > 0])
    error_message = "An index with projection_type INCLUDE must list non_key_attributes."
  }

  validation {
    condition     = length(var.global_secondary_indexes) == length(distinct([for index in var.global_secondary_indexes : index.name]))
    error_message = "Each index needs a different name."
  }
}

variable "ttl_attribute" {
  description = "Attribute holding the time, in seconds since the epoch, after which an item is deleted. With null, items never expire."
  type        = string
  default     = null
}

variable "stream_view_type" {
  description = "Stream item changes, with this content: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE or NEW_AND_OLD_IMAGES. With null there is no stream."
  type        = string
  default     = null

  validation {
    condition     = var.stream_view_type == null ? true : contains(["KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream_view_type)
    error_message = "stream_view_type must be KEYS_ONLY, NEW_IMAGE, OLD_IMAGE or NEW_AND_OLD_IMAGES, or null for no stream."
  }
}

variable "provisioned_capacity" {
  description = "Pay for a fixed range of capacity that autoscaling moves within, for the table and every index. With null the table is billed per request, which suits unpredictable or low traffic."
  type = object({
    read_min           = number
    read_max           = number
    write_min          = number
    write_max          = number
    target_utilization = optional(number, 70)
  })
  default = null

  validation {
    condition     = var.provisioned_capacity == null ? true : var.provisioned_capacity.read_min >= 1 && var.provisioned_capacity.write_min >= 1 && var.provisioned_capacity.read_max >= var.provisioned_capacity.read_min && var.provisioned_capacity.write_max >= var.provisioned_capacity.write_min
    error_message = "Minimums must be at least 1 and no greater than their maximums."
  }

  validation {
    condition     = var.provisioned_capacity == null ? true : var.provisioned_capacity.target_utilization >= 20 && var.provisioned_capacity.target_utilization <= 90
    error_message = "target_utilization must be between 20 and 90 percent."
  }
}

variable "deletion_protection" {
  description = "Refuse to delete the table. Turn off only in an environment whose data is disposable."
  type        = bool
  default     = true
}
