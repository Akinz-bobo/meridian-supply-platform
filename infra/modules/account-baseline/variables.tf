variable "name" {
  description = "Name of the access analyzer. Take it from the context module's prefix."
  type        = string
}

variable "tags" {
  description = "Tags for the resources that support them. Take them from the context module."
  type        = map(string)
}

variable "ebs_kms_key_arn" {
  description = "Key that encrypts new EBS volumes by default. Pass the data key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.ebs_kms_key_arn))
    error_message = "Give the ARN of a KMS key."
  }
}

variable "minimum_password_length" {
  description = "Shortest password an IAM user may set."
  type        = number
  default     = 14

  validation {
    condition     = var.minimum_password_length >= 14
    error_message = "The minimum password length may not be lower than 14."
  }
}
