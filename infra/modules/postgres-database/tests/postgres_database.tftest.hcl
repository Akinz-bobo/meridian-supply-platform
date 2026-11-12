# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed.

mock_provider "aws" {}

variables {
  name                = "meridian-prod-catalog-db"
  database_name       = "catalog"
  data_classification = "confidential"
  subnet_ids          = ["subnet-data-a", "subnet-data-b", "subnet-data-c"]
  security_group_ids  = ["sg-data"]
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
  secrets_kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/22222222-2222-2222-2222-222222222222"
  logs_kms_key_arn    = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
  tags = {
    Project = "meridian"
  }
}

run "is_never_publicly_accessible" {
  command = plan

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "The database must not be publicly accessible. There is no input for it."
  }
}

run "is_encrypted_with_the_data_key" {
  command = plan

  assert {
    condition     = aws_db_instance.this.storage_encrypted && aws_db_instance.this.kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
    error_message = "Storage must be encrypted with the key that was passed."
  }
}

run "lets_rds_manage_the_master_password" {
  command = plan

  assert {
    condition     = aws_db_instance.this.manage_master_user_password
    error_message = "RDS must manage the master password."
  }

  assert {
    condition     = aws_db_instance.this.password == null && aws_db_instance.this.password_wo == null
    error_message = "No password may be given to Terraform, stored or write-only."
  }

  assert {
    condition     = aws_db_instance.this.master_user_secret_kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/22222222-2222-2222-2222-222222222222"
    error_message = "The master password must be encrypted with the secrets key."
  }
}

run "requires_tls_and_logs_slow_statements_and_connections" {
  command = plan

  assert {
    condition     = { for parameter in aws_db_parameter_group.this.parameter : parameter.name => parameter.value }["rds.force_ssl"] == "1"
    error_message = "Connections without TLS must be refused."
  }

  assert {
    condition     = { for parameter in aws_db_parameter_group.this.parameter : parameter.name => parameter.value }["log_min_duration_statement"] == "1000"
    error_message = "Statements slower than a second are logged by default."
  }

  assert {
    condition     = { for parameter in aws_db_parameter_group.this.parameter : parameter.name => parameter.value }["log_connections"] == "1"
    error_message = "Connections must be logged."
  }
}

run "picks_the_parameter_family_from_the_version" {
  command = plan

  variables {
    engine_version = "17.4"
  }

  assert {
    condition     = aws_db_parameter_group.this.family == "postgres17"
    error_message = "The parameter group family follows the major version."
  }
}

run "is_highly_available_and_recoverable_by_default" {
  command = plan

  assert {
    condition     = aws_db_instance.this.multi_az
    error_message = "A standby in a second zone is the default."
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period == 14
    error_message = "Two weeks of backups is the default."
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection
    error_message = "Deletion protection is on by default."
  }

  assert {
    condition     = aws_db_instance.this.skip_final_snapshot == false && aws_db_instance.this.final_snapshot_identifier == "meridian-prod-catalog-db-final"
    error_message = "A final snapshot is taken by default, named after the database."
  }

  assert {
    condition     = aws_db_instance.this.copy_tags_to_snapshot
    error_message = "Snapshots must inherit the tags, including the classification."
  }
}

run "a_disposable_database_can_be_torn_down" {
  command = plan

  variables {
    multi_az            = false
    deletion_protection = false
    skip_final_snapshot = true
  }

  assert {
    condition     = aws_db_instance.this.final_snapshot_identifier == null
    error_message = "With skip_final_snapshot no snapshot name is set."
  }
}

run "sends_logs_to_an_encrypted_group_with_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.postgresql.name == "/aws/rds/instance/meridian-prod-catalog-db/postgresql"
    error_message = "The log group must have the name RDS writes to, so that it is created with our settings and not RDS's."
  }

  assert {
    condition     = aws_cloudwatch_log_group.postgresql.retention_in_days == 90 && aws_cloudwatch_log_group.postgresql.kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
    error_message = "The log group needs retention and the logs key."
  }

  assert {
    condition     = contains(aws_db_instance.this.enabled_cloudwatch_logs_exports, "postgresql")
    error_message = "The PostgreSQL log must be exported."
  }
}

run "allows_iam_authentication" {
  command = plan

  assert {
    condition     = aws_db_instance.this.iam_database_authentication_enabled
    error_message = "IAM database authentication must be on, so applications can connect without a stored password."
  }
}

run "grows_storage_up_to_a_ceiling" {
  command = plan

  assert {
    condition     = aws_db_instance.this.storage_type == "gp3" && aws_db_instance.this.allocated_storage == 20 && aws_db_instance.this.max_allocated_storage == 100
    error_message = "Storage is gp3, starts at 20 gigabytes and may grow to 100."
  }
}

run "carries_its_classification_as_a_tag" {
  command = plan

  assert {
    condition     = aws_db_instance.this.tags["DataClassification"] == "confidential"
    error_message = "The classification must become the DataClassification tag."
  }
}

run "encrypts_performance_data_with_the_data_key" {
  command = plan

  assert {
    condition     = aws_db_instance.this.performance_insights_enabled && aws_db_instance.this.performance_insights_kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
    error_message = "Performance Insights must use the data key."
  }
}

run "rejects_turning_backups_off" {
  command = plan

  variables {
    backup_retention_days = 0
  }

  expect_failures = [var.backup_retention_days]
}

run "rejects_a_guessable_master_username" {
  command = plan

  variables {
    master_username = "postgres"
  }

  expect_failures = [var.master_username]
}

run "rejects_a_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-data-a"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_a_database_with_no_security_group" {
  command = plan

  variables {
    security_group_ids = []
  }

  expect_failures = [var.security_group_ids]
}

run "rejects_a_ceiling_below_the_starting_size" {
  command = plan

  variables {
    allocated_storage_gb     = 200
    max_allocated_storage_gb = 100
  }

  expect_failures = [var.max_allocated_storage_gb]
}

run "rejects_an_end_of_life_version" {
  command = plan

  variables {
    engine_version = "11"
  }

  expect_failures = [var.engine_version]
}

run "rejects_a_database_without_a_customer_managed_key" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_logging_every_statement" {
  command = plan

  variables {
    slow_statement_milliseconds = 0
  }

  expect_failures = [var.slow_statement_milliseconds]
}
