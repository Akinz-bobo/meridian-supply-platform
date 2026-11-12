variable "name" {
  description = "Identifier of the replication group, and the name of its subnet group, parameter group and user group. Build it from the context module's prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 40
    error_message = "A replication group identifier starts with a letter, uses lower case letters, digits and single hyphens, and is at most 40 characters."
  }
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "description" {
  description = "What the cache holds, in one sentence."
  type        = string

  validation {
    condition     = length(var.description) >= 10
    error_message = "Describe what the cache holds in at least a few words."
  }
}

variable "account_id" {
  description = "Account the cache is in. Used to name it exactly in the connect policies."
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

variable "subnet_ids" {
  description = "Subnets the cache nodes may be placed in. Pass the data subnets."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "A cache subnet group needs subnets in at least two zones."
  }
}

variable "security_group_ids" {
  description = "Security groups attached to the cache. Pass the data security group."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "Attach at least one security group."
  }
}

variable "kms_key_arn" {
  description = "ARN of the key that encrypts the cache and its snapshots at rest. Pass the data key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "Give the ARN of a KMS key. A cache is not created without a customer managed key."
  }
}

variable "logs_kms_key_arn" {
  description = "ARN of the key that encrypts the slow log's log group. Pass the logs key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.logs_kms_key_arn))
    error_message = "Give the ARN of a KMS key."
  }
}

variable "log_group_name" {
  description = "Name of the log group for the slow log, a path under /<project>/<environment>/."
  type        = string

  validation {
    condition     = startswith(var.log_group_name, "/")
    error_message = "Log group names in this platform are paths and start with a slash."
  }
}

variable "log_retention_days" {
  description = "How long the slow log is kept."
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731], var.log_retention_days)
    error_message = "Retention must be a value CloudWatch accepts and at least 30 days: 30, 60, 90, 120, 150, 180, 365, 400, 545 or 731."
  }
}

variable "users" {
  description = "Clients of the cache, keyed by a short name such as the service. Each authenticates with IAM and is limited by an access string in Valkey ACL syntax, for example: on ~stock:* +@read +@write -@dangerous."
  type = map(object({
    access_string = string
  }))

  validation {
    condition     = length(var.users) > 0
    error_message = "Name at least one user. There is no default user, so with no users nothing could connect."
  }

  validation {
    condition     = alltrue([for key in keys(var.users) : can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", key))])
    error_message = "User names are lower case words separated by hyphens."
  }

  validation {
    condition     = alltrue([for user in values(var.users) : startswith(user.access_string, "on ")])
    error_message = "An access string starts with on. A user that is off cannot connect."
  }

  validation {
    condition     = alltrue([for user in values(var.users) : !strcontains(user.access_string, "+@all") && !strcontains(user.access_string, "allcommands") && !strcontains(user.access_string, "+@admin") && !strcontains(user.access_string, "+@dangerous")])
    error_message = "A user may not be granted every command, or the admin or dangerous command categories. Grant the categories it needs, such as +@read +@write."
  }

  validation {
    condition     = alltrue([for user in values(var.users) : !can(regex("(^| )(~\\*|allkeys)( |$)", user.access_string))])
    error_message = "A user may not be granted every key. Give it a key pattern with a prefix, such as ~stock:*."
  }
}

variable "engine_version" {
  description = "Valkey version, as major.minor."
  type        = string
  default     = "8.0"

  validation {
    condition     = can(regex("^[7-9]\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be Valkey 7.2 or later, as major.minor, for example 8.0."
  }
}

variable "node_type" {
  description = "Size of each node."
  type        = string
  default     = "cache.t4g.small"

  validation {
    condition     = startswith(var.node_type, "cache.")
    error_message = "An ElastiCache node type starts with cache., for example cache.t4g.small."
  }
}

variable "replicas" {
  description = "Read replicas in other zones. With at least one, a failed primary is replaced automatically. Zero means an outage of the node is an outage of the cache."
  type        = number
  default     = 1

  validation {
    condition     = var.replicas >= 0 && var.replicas <= 5
    error_message = "replicas must be between 0 and 5."
  }
}

variable "eviction_policy" {
  description = "What happens when memory is full. The default evicts the least recently used key."
  type        = string
  default     = "allkeys-lru"

  validation {
    condition     = contains(["allkeys-lru", "allkeys-lfu", "volatile-lru", "volatile-lfu", "volatile-ttl"], var.eviction_policy)
    error_message = "eviction_policy must evict something: allkeys-lru, allkeys-lfu, volatile-lru, volatile-lfu or volatile-ttl. noeviction turns a full cache into an outage."
  }
}

variable "snapshot_retention_days" {
  description = "Days of daily snapshots. Zero turns snapshots off, which suits a cache that is cheap to refill."
  type        = number
  default     = 1

  validation {
    condition     = var.snapshot_retention_days >= 0 && var.snapshot_retention_days <= 35
    error_message = "snapshot_retention_days must be between 0 and 35."
  }
}

variable "snapshot_window" {
  description = "Daily time, in UTC, when the snapshot is taken."
  type        = string
  default     = "01:00-02:00"
}

variable "maintenance_window" {
  description = "Weekly time, in UTC, when patches are applied. Must not overlap the snapshot window."
  type        = string
  default     = "sun:03:00-sun:04:00"
}

variable "apply_immediately" {
  description = "Apply changes at once and not in the next maintenance window."
  type        = bool
  default     = false
}
