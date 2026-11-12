# A PostgreSQL database on RDS.
#
# Always: in the given private subnets and never publicly accessible,
# encrypted with a customer managed key, connections required to use TLS,
# and a master password that RDS creates and rotates in Secrets Manager
# without Terraform ever seeing it.
#
# By default, and switched off only where data is disposable: a standby in
# a second zone, two weeks of backups, a final snapshot when the database
# is deleted, and deletion protection.

locals {
  tags = merge(var.tags, { DataClassification = var.data_classification })

  # RDS decides this name. It cannot follow the platform's path convention.
  log_group_name = "/aws/rds/instance/${var.name}/postgresql"

  # postgres16 from 16 or 16.4.
  family = "postgres${split(".", var.engine_version)[0]}"
}

resource "aws_db_subnet_group" "this" {
  name        = var.name
  description = "Subnets of the data tier for ${var.name}."
  subnet_ids  = var.subnet_ids

  tags = var.tags
}

resource "aws_db_parameter_group" "this" {
  name        = var.name
  family      = local.family
  description = "Parameters for ${var.name}: TLS required, slow statements and connections logged."

  # Refuse any connection that is not encrypted.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Log statements slower than this many milliseconds, to find the queries
  # worth fixing.
  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.slow_statement_milliseconds)
  }

  # Who connected and when. The audit record of access to the database.
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = var.tags

  lifecycle {
    # A parameter group in use cannot be deleted. Creating the replacement
    # first lets the instance move to it.
    create_before_destroy = true
  }
}

# Created before the instance, so that the group has the platform's
# retention and key. Left to RDS, it would be created on the first log line
# with no retention and no customer managed key.
resource "aws_cloudwatch_log_group" "postgresql" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

resource "aws_db_instance" "this" {
  identifier = var.name

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class
  db_name        = var.database_name

  # Storage. gp3 gives baseline performance that does not depend on size,
  # and storage grows by itself up to the maximum.
  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  # Credentials. RDS generates the master password, stores it in Secrets
  # Manager under the given key and rotates it. It is in neither the
  # configuration nor the state.
  username                      = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.secrets_kms_key_arn

  # Applications authenticate with short-lived IAM tokens where they can,
  # so that most of them hold no database password at all.
  iam_database_authentication_enabled = true

  # Network.
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false

  # The port is left to the engine's default, 5432, and consumers read it
  # from the output. Nothing should assume it.

  parameter_group_name = aws_db_parameter_group.this.name

  # Availability.
  multi_az = var.multi_az

  # Recovery.
  backup_retention_period   = var.backup_retention_days
  backup_window             = var.backup_window
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final"

  # Maintenance.
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  # Observability.
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
  performance_insights_enabled          = var.performance_insights
  performance_insights_kms_key_id       = var.performance_insights ? var.kms_key_arn : null
  performance_insights_retention_period = var.performance_insights ? 7 : null

  tags = local.tags

  depends_on = [aws_cloudwatch_log_group.postgresql]
}
