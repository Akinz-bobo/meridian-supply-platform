variable "name" {
  description = "Identifier of the database instance, and the name of its subnet group and parameter group. Build it from the context module's prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 63
    error_message = "An instance identifier starts with a letter, uses lower case letters, digits and single hyphens, and is at most 63 characters."
  }
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "data_classification" {
  description = "How sensitive the contents are: public, internal, confidential or restricted. Becomes the DataClassification tag on the instance."
  type        = string

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be public, internal, confidential or restricted. The levels are defined in docs/architecture/data.md."
  }
}

variable "database_name" {
  description = "Name of the database created inside the instance."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "A database name starts with a letter and uses lower case letters, digits and underscores."
  }
}

variable "subnet_ids" {
  description = "Subnets the database may be placed in. Pass the data subnets, in at least two zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "A database subnet group needs subnets in at least two zones."
  }
}

variable "security_group_ids" {
  description = "Security groups attached to the database. Pass the data security group."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "Attach at least one security group. Without one the database joins the VPC's default group."
  }
}

variable "kms_key_arn" {
  description = "ARN of the key that encrypts storage, snapshots and performance data. Pass the data key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "Give the ARN of a KMS key. A database is not created without a customer managed key."
  }
}

variable "secrets_kms_key_arn" {
  description = "ARN of the key that encrypts the master password in Secrets Manager. Pass the secrets key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.secrets_kms_key_arn))
    error_message = "Give the ARN of a KMS key."
  }
}

variable "logs_kms_key_arn" {
  description = "ARN of the key that encrypts the database's log group. Pass the logs key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.logs_kms_key_arn))
    error_message = "Give the ARN of a KMS key."
  }
}

variable "engine_version" {
  description = "PostgreSQL version, as a major version (16) or an exact one (16.4). With a major version, RDS chooses the minor version and upgrades it in the maintenance window."
  type        = string
  default     = "16"

  validation {
    condition     = can(regex("^(1[4-9]|[2-9][0-9])(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must be PostgreSQL 14 or later, for example 16 or 16.4."
  }
}

variable "instance_class" {
  description = "Size of the instance."
  type        = string
  default     = "db.t4g.medium"

  validation {
    condition     = startswith(var.instance_class, "db.")
    error_message = "An RDS instance class starts with db., for example db.t4g.medium."
  }
}

variable "allocated_storage_gb" {
  description = "Storage the database starts with, in gigabytes."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage_gb >= 20
    error_message = "gp3 storage starts at 20 gigabytes."
  }
}

variable "max_allocated_storage_gb" {
  description = "Storage the database may grow to by itself, in gigabytes. A ceiling, so that a runaway table fills a known amount and not the budget."
  type        = number
  default     = 100

  validation {
    condition     = var.max_allocated_storage_gb >= 20
    error_message = "The storage ceiling must be at least 20 gigabytes."
  }

  validation {
    condition     = var.max_allocated_storage_gb >= var.allocated_storage_gb
    error_message = "The storage ceiling must not be lower than the starting size."
  }
}

variable "master_username" {
  description = "Name of the master user. Its password is managed by RDS."
  type        = string
  default     = "meridian_admin"

  validation {
    condition     = !contains(["postgres", "admin", "root", "rdsadmin"], var.master_username) && can(regex("^[a-z][a-z0-9_]{0,62}$", var.master_username))
    error_message = "Choose a master username that is not postgres, admin, root or rdsadmin. The first three are the names an attacker tries, and the last is reserved by RDS."
  }
}

variable "multi_az" {
  description = "Keep a synchronous standby in a second zone and fail over to it automatically."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Days of automated backups, which is also how far back the database can be restored to a point in time."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days. Zero turns backups off, which is not allowed."
  }
}

variable "backup_window" {
  description = "Daily time, in UTC, when the automated backup is taken."
  type        = string
  default     = "01:00-02:00"
}

variable "maintenance_window" {
  description = "Weekly time, in UTC, when patches and minor upgrades are applied. Must not overlap the backup window."
  type        = string
  default     = "sun:03:00-sun:04:00"
}

variable "deletion_protection" {
  description = "Refuse to delete the database. Turn off only in an environment whose data is disposable."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Delete the database without taking a last snapshot. Turn on only in an environment whose data is disposable."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply changes that need a restart at once and not in the next maintenance window. Causes downtime on a single-zone instance."
  type        = bool
  default     = false
}

variable "performance_insights" {
  description = "Record database load by statement, wait and user, kept for 7 days and encrypted with the data key."
  type        = bool
  default     = true
}

variable "slow_statement_milliseconds" {
  description = "Log statements that take longer than this."
  type        = number
  default     = 1000

  validation {
    condition     = var.slow_statement_milliseconds >= 100
    error_message = "A threshold under 100 milliseconds logs most statements, which is costly and can put data in the logs."
  }
}

variable "log_retention_days" {
  description = "How long the database's logs are kept."
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731], var.log_retention_days)
    error_message = "Retention must be a value CloudWatch accepts and at least 30 days: 30, 60, 90, 120, 150, 180, 365, 400, 545 or 731."
  }
}
