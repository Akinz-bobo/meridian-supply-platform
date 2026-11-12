# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed. The read policy is tested in read_policy.tftest.hcl, which needs
# the real provider to render JSON.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  path          = "/meridian/prod/catalog"
  account_id    = "333333333333"
  kms_key_arn   = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
  kms_key_alias = "alias/meridian-prod-secrets"
  tags = {
    Project = "meridian"
  }

  parameters = {
    log-level = "info"
  }

  secrets = {
    webhook-signing-key = {
      description = "Signs webhooks sent to suppliers."
      generate    = {}
    }
    partner-api-token = {
      description = "Token for the partner's price feed."
    }
  }
}

run "stores_configuration_under_the_services_config_path" {
  command = plan

  assert {
    condition     = aws_ssm_parameter.config["log-level"].name == "/meridian/prod/catalog/config/log-level"
    error_message = "A parameter is stored at <path>/config/<key>."
  }

  assert {
    condition     = output.parameter_path == "/meridian/prod/catalog/config"
    error_message = "The parameter path output is <path>/config."
  }
}

run "stores_secrets_under_the_services_secrets_path" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.this["partner-api-token"].name == "/meridian/prod/catalog/secrets/partner-api-token"
    error_message = "A secret is stored at <path>/secrets/<name>."
  }
}

run "encrypts_every_secret_with_the_given_key" {
  command = plan

  assert {
    condition     = alltrue([for secret in aws_secretsmanager_secret.this : secret.kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"])
    error_message = "Every secret must use the key that was passed, not the AWS managed key."
  }
}

run "keeps_a_deleted_secret_recoverable_for_thirty_days" {
  command = plan

  assert {
    condition     = alltrue([for secret in aws_secretsmanager_secret.this : secret.recovery_window_in_days == 30])
    error_message = "The default recovery window is 30 days."
  }
}

run "generates_a_value_only_where_asked" {
  command = plan

  assert {
    condition     = toset(keys(aws_secretsmanager_secret_version.generated)) == toset(["webhook-signing-key"])
    error_message = "Only secrets with a generate block get a value from Terraform."
  }
}

run "tracks_a_generated_value_by_version_and_not_by_content" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret_version.generated["webhook-signing-key"].secret_string_wo_version == 1
    error_message = "The version number is what Terraform stores."
  }

  # A write-only argument is never readable, at plan or after apply.
  assert {
    condition     = aws_secretsmanager_secret_version.generated["webhook-signing-key"].secret_string_wo == null
    error_message = "The secret value must not be readable from the planned resource."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.generated["webhook-signing-key"].secret_string == null
    error_message = "The ordinary, stored secret_string argument must not be used."
  }
}

run "rotates_only_where_a_function_is_given" {
  command = plan

  variables {
    secrets = {
      database-credentials = {
        description = "Application user of the catalog database."
        rotation = {
          lambda_arn = "arn:aws:lambda:eu-west-1:333333333333:function:meridian-prod-catalog-rotate"
        }
      }
      partner-api-token = {
        description = "Token for the partner's price feed."
      }
    }
  }

  assert {
    condition     = toset(keys(aws_secretsmanager_secret_rotation.this)) == toset(["database-credentials"])
    error_message = "Only secrets with a rotation block are rotated."
  }

  assert {
    condition     = one(aws_secretsmanager_secret_rotation.this["database-credentials"].rotation_rules).automatically_after_days == 30
    error_message = "The default rotation interval is 30 days."
  }
}

run "rejects_a_path_that_covers_more_than_one_service" {
  command = plan

  variables {
    path = "/meridian/prod"
  }

  expect_failures = [var.path]
}

run "rejects_a_path_with_a_trailing_slash" {
  command = plan

  variables {
    path = "/meridian/prod/catalog/"
  }

  expect_failures = [var.path]
}

run "rejects_a_secret_put_among_the_plain_parameters" {
  command = plan

  variables {
    parameters = {
      database-password = "hunter2"
    }
  }

  expect_failures = [var.parameters]
}

run "rejects_a_short_generated_secret" {
  command = plan

  variables {
    secrets = {
      signing-key = {
        description = "Too short to be a key."
        generate    = { length = 8 }
      }
    }
  }

  expect_failures = [var.secrets]
}

run "rejects_rotation_slower_than_ninety_days" {
  command = plan

  variables {
    secrets = {
      database-credentials = {
        description = "Rotated too rarely."
        rotation = {
          lambda_arn               = "arn:aws:lambda:eu-west-1:333333333333:function:rotate"
          automatically_after_days = 365
        }
      }
    }
  }

  expect_failures = [var.secrets]
}

run "rejects_immediate_deletion" {
  command = plan

  variables {
    recovery_window_in_days = 0
  }

  expect_failures = [var.recovery_window_in_days]
}
