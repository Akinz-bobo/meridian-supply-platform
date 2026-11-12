# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name        = "meridian-prod-data"
  description = "Encrypts databases, tables and buckets in production."
  account_id  = "333333333333"
  tags = {
    Project = "meridian"
  }
}

run "always_rotates" {
  command = plan

  assert {
    condition     = aws_kms_key.this.enable_key_rotation
    error_message = "Rotation is not optional."
  }

}

run "can_rotate_more_often_than_yearly" {
  command = plan

  variables {
    rotation_period_in_days = 90
  }

  assert {
    condition     = aws_kms_key.this.rotation_period_in_days == 90
    error_message = "A shorter rotation period must reach the key."
  }
}

run "waits_thirty_days_before_deletion_by_default" {
  command = plan

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30
    error_message = "The default deletion window is the longest AWS allows."
  }
}

run "is_reachable_by_alias" {
  command = plan

  assert {
    condition     = aws_kms_alias.this.name == "alias/meridian-prod-data"
    error_message = "The alias is alias/<name>."
  }
}

run "lets_the_account_manage_access_through_iam" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.key.statement) == 1
    error_message = "With no service principals the key policy has exactly one statement."
  }

  assert {
    condition     = one(data.aws_iam_policy_document.key.statement[0].principals).identifiers == toset(["arn:aws:iam::333333333333:root"])
    error_message = "The account root must be the principal, which delegates access decisions to IAM."
  }
}

run "limits_services_to_this_account" {
  command = plan

  variables {
    service_principals = ["logs.eu-west-1.amazonaws.com"]
  }

  assert {
    condition     = length(data.aws_iam_policy_document.key.statement) == 2
    error_message = "A service principal adds a second statement."
  }

  assert {
    condition = data.aws_iam_policy_document.key.statement[1].condition == toset([{
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = tolist(["333333333333"])
    }])
    error_message = "A service may use the key only for requests made on behalf of this account."
  }

  assert {
    condition     = !contains(data.aws_iam_policy_document.key.statement[1].actions, "kms:*")
    error_message = "A service gets the cryptographic actions it needs and no administrative ones."
  }
}

run "rejects_a_name_that_already_has_the_alias_prefix" {
  command = plan

  variables {
    name = "alias/meridian-prod-data"
  }

  expect_failures = [var.name]
}

run "rejects_a_deletion_window_shorter_than_two_weeks" {
  command = plan

  variables {
    deletion_window_in_days = 7
  }

  expect_failures = [var.deletion_window_in_days]
}

run "rejects_rotation_less_often_than_yearly" {
  command = plan

  variables {
    rotation_period_in_days = 730
  }

  expect_failures = [var.rotation_period_in_days]
}

run "rejects_a_principal_that_is_not_a_service" {
  command = plan

  variables {
    service_principals = ["arn:aws:iam::999999999999:root"]
  }

  expect_failures = [var.service_principals]
}

run "rejects_an_empty_description" {
  command = plan

  variables {
    description = "key"
  }

  expect_failures = [var.description]
}
