variable "name" {
  description = "Name of the topic. Build it from the context module's prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 256
    error_message = "A topic name starts with a letter and uses lower case letters, digits and single hyphens."
  }
}

variable "tags" {
  description = "Tags for the topic. Take them from the context module."
  type        = map(string)
}

variable "display_name" {
  description = "Name shown as the sender of an email or text message."
  type        = string
  default     = null
}

variable "account_id" {
  description = "Account the topic is in. Only this account's services and principals may publish or subscribe."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "kms_key_arn" {
  description = "ARN of the key that encrypts messages in the topic. Pass the messaging key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "Give the ARN of a KMS key. A topic is not created without a customer managed key."
  }
}

variable "publishing_services" {
  description = "AWS services allowed to publish to the topic for this account, for example cloudwatch.amazonaws.com for alarms and events.amazonaws.com for rules on the bus. Each must also be named in the key policy of the key."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for service in var.publishing_services : endswith(service, ".amazonaws.com")])
    error_message = "A service principal ends in .amazonaws.com, for example cloudwatch.amazonaws.com."
  }
}

variable "subscriptions" {
  description = "Where messages are delivered, keyed by a short name. protocol is one of email, https, sqs, lambda, sms or firehose."
  type = map(object({
    protocol             = string
    endpoint             = string
    raw_message_delivery = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for subscription in values(var.subscriptions) : contains(["email", "https", "sqs", "lambda", "sms", "firehose"], subscription.protocol)])
    error_message = "protocol must be one of email, https, sqs, lambda, sms or firehose. Plain http is not accepted: it would send messages unencrypted."
  }
}
