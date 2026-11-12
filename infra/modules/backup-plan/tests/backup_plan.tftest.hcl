# Plan-only tests. The provider is real with placeholder credentials so the
# rendered policies can be read. Nothing is called: no AWS account or
# emulator is needed.

provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  name        = "meridian-prod-backup"
  account_id  = "333333333333"
  kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/44444444-4444-4444-4444-444444444444"
  tags = {
    Project = "meridian"
  }
}

run "encrypts_the_vault_with_the_given_key" {
  command = plan

  assert {
    condition     = aws_backup_vault.this.kms_key_arn == "arn:aws:kms:eu-west-1:333333333333:key/44444444-4444-4444-4444-444444444444"
    error_message = "The vault must use the key that was passed."
  }
}

run "nobody_deletes_a_recovery_point_by_hand" {
  command = plan

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.vault.json).Statement[0].Effect == "Deny" && jsondecode(data.aws_iam_policy_document.vault.json).Statement[0].Principal == "*"
    error_message = "The vault policy must deny every principal."
  }

  assert {
    condition     = toset(jsondecode(data.aws_iam_policy_document.vault.json).Statement[0].Action) == toset(["backup:DeleteRecoveryPoint", "backup:UpdateRecoveryPointLifecycle"])
    error_message = "Deleting a recovery point and shortening its life must both be denied."
  }
}

run "locks_the_vault_by_default" {
  command = plan

  assert {
    condition     = aws_backup_vault_lock_configuration.this[0].min_retention_days == 7
    error_message = "The vault is locked with a minimum retention of 7 days by default."
  }

  assert {
    condition     = aws_backup_vault.this.force_destroy == false
    error_message = "A vault with recovery points must not be deletable by default."
  }
}

run "a_disposable_vault_has_no_lock" {
  command = plan

  variables {
    lock_min_retention_days = null
    force_destroy           = true
  }

  assert {
    condition     = length(aws_backup_vault_lock_configuration.this) == 0
    error_message = "With no minimum retention there is no lock."
  }
}

run "backs_up_daily_and_keeps_five_weeks_by_default" {
  command = plan

  assert {
    condition     = one(aws_backup_plan.this.rule).schedule == "cron(0 2 * * ? *)" && one(one(aws_backup_plan.this.rule).lifecycle).delete_after == 35
    error_message = "The default rule runs daily at 02:00 UTC and keeps backups for 35 days."
  }
}

run "selects_stores_by_tag_and_not_by_name" {
  command = plan

  assert {
    condition     = one(aws_backup_selection.this.selection_tag).key == "Backup" && one(aws_backup_selection.this.selection_tag).value == "daily"
    error_message = "A store opts in with the tag Backup = daily."
  }

  assert {
    condition     = aws_backup_selection.this.resources == null || length(aws_backup_selection.this.resources) == 0
    error_message = "No store may be listed by name. Selection is by tag only."
  }
}

run "the_service_role_can_only_take_backups" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "backup.amazonaws.com" && jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "333333333333"
    error_message = "Only the backup service, acting for this account, may assume the role."
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup" && aws_iam_role_policy_attachment.this.policy_arn == aws_iam_role.this.permissions_boundary
    error_message = "The role's permissions and its boundary are both AWS's backup policy, so it can never be given more."
  }
}

run "takes_several_rules" {
  command = plan

  variables {
    rules = {
      daily   = { schedule = "cron(0 2 * * ? *)", retention_days = 35 }
      monthly = { schedule = "cron(0 3 1 * ? *)", retention_days = 365 }
    }
  }

  assert {
    condition     = toset([for rule in aws_backup_plan.this.rule : rule.rule_name]) == toset(["daily", "monthly"])
    error_message = "Each rule in the input becomes a rule of the plan."
  }
}

run "rejects_backups_kept_for_less_than_a_week" {
  command = plan

  variables {
    rules = {
      daily = { schedule = "cron(0 2 * * ? *)", retention_days = 3 }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_rule_shorter_than_the_vault_lock" {
  command = plan

  variables {
    lock_min_retention_days = 30
    rules = {
      daily = { schedule = "cron(0 2 * * ? *)", retention_days = 14 }
    }
  }

  expect_failures = [var.lock_min_retention_days]
}

run "rejects_a_schedule_that_is_not_a_cron_expression" {
  command = plan

  variables {
    rules = {
      daily = { schedule = "every day at two", retention_days = 35 }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_vault_without_a_customer_managed_key" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}
