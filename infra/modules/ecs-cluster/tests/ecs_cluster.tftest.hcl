# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed.

mock_provider "aws" {}

variables {
  name                = "meridian-prod-compute"
  exec_log_group_name = "/meridian/prod/compute/ecs-exec"
  logs_kms_key_arn    = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
  tags = {
    Project = "meridian"
  }
}

run "reports_metrics_per_container" {
  command = plan

  assert {
    condition     = one(aws_ecs_cluster.this.setting).name == "containerInsights" && one(aws_ecs_cluster.this.setting).value == "enabled"
    error_message = "Container insights must be on."
  }
}

run "records_every_shell_session_encrypted" {
  command = plan

  assert {
    condition     = one(one(aws_ecs_cluster.this.configuration).execute_command_configuration).logging == "OVERRIDE"
    error_message = "Shell sessions must be logged to the log group this module creates."
  }

  assert {
    condition     = one(one(one(aws_ecs_cluster.this.configuration).execute_command_configuration).log_configuration).cloud_watch_encryption_enabled
    error_message = "The session log must be encrypted."
  }

  assert {
    condition     = one(one(aws_ecs_cluster.this.configuration).execute_command_configuration).kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
    error_message = "The session itself must be encrypted with the given key."
  }
}

run "keeps_session_records_for_a_year" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.exec.retention_in_days == 365 && aws_cloudwatch_log_group.exec.kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
    error_message = "Session records are kept for a year, encrypted with the logs key."
  }
}

run "uses_on_demand_capacity_unless_asked" {
  command = plan

  assert {
    condition     = one(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy).capacity_provider == "FARGATE"
    error_message = "The default capacity provider is on-demand Fargate."
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this.capacity_providers, "FARGATE_SPOT")
    error_message = "Spot capacity must be available to services that ask for it."
  }
}

run "rejects_a_log_group_name_that_is_not_a_path" {
  command = plan

  variables {
    exec_log_group_name = "ecs-exec"
  }

  expect_failures = [var.exec_log_group_name]
}

run "rejects_a_short_retention" {
  command = plan

  variables {
    log_retention_days = 7
  }

  expect_failures = [var.log_retention_days]
}
