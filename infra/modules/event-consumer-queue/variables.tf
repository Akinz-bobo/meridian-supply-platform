variable "name" {
  description = "Name of the queue: <prefix>-<event in kebab case>, where the prefix comes from the context module of the consuming service. The dead-letter queue adds -dlq."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 60
    error_message = "The name starts with a letter, uses lower case letters, digits and single hyphens, and is at most 60 characters, which leaves room for the suffixes of the dead-letter queue and the alarm."
  }
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module of the consuming service."
  type        = map(string)
}

variable "account_id" {
  description = "Account the queue is in."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "bus_name" {
  description = "Name of the event bus the rule is created on."
  type        = string
}

variable "source_prefix" {
  description = "First part of every event's source on the bus. The rule matches events whose source starts with it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*$", var.source_prefix))
    error_message = "The source prefix is one lower case word, for example meridian."
  }
}

variable "event_types" {
  description = "Event types delivered to the queue, as they appear in the event catalogue, for example GoodsReceived."
  type        = set(string)

  validation {
    condition     = length(var.event_types) > 0
    error_message = "Name at least one event type. A queue that matches nothing receives nothing."
  }

  validation {
    condition     = alltrue([for type in var.event_types : can(regex("^[A-Z][a-z0-9]+([A-Z][a-z0-9]+)+$", type))])
    error_message = "Event types are PascalCase with at least two words, as in the event contract, for example GoodsReceived."
  }
}

variable "kms_key_arn" {
  description = "ARN of the key that encrypts both queues. Pass the messaging key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "Give the ARN of a KMS key. A queue is not created without a customer managed key."
  }
}

variable "max_receive_count" {
  description = "Times a message may be received without being deleted before it is moved to the dead-letter queue."
  type        = number
  default     = 5

  validation {
    condition     = var.max_receive_count >= 2 && var.max_receive_count <= 20
    error_message = "max_receive_count must be between 2 and 20. One gives a transient failure no second chance."
  }
}

variable "visibility_timeout_seconds" {
  description = "How long a received message is hidden from other receivers. Set it to several times the consumer's longest processing time, or a slow message is processed twice."
  type        = number
  default     = 60

  validation {
    condition     = var.visibility_timeout_seconds >= 30 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 30 seconds and 12 hours."
  }
}

variable "retention_days" {
  description = "Days an unprocessed message is kept in the queue before SQS discards it."
  type        = number
  default     = 4

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 14
    error_message = "retention_days must be between 1 and 14."
  }
}

variable "dead_letter_retention_days" {
  description = "Days a failed message is kept in the dead-letter queue."
  type        = number
  default     = 14

  validation {
    condition     = var.dead_letter_retention_days >= 7 && var.dead_letter_retention_days <= 14
    error_message = "Keep failed messages for 7 to 14 days. They must outlast a weekend and the investigation."
  }
}

variable "alarm_actions" {
  description = "ARNs notified when the dead-letter queue alarm changes state. Pass the alarms topic."
  type        = list(string)
  default     = []
}
