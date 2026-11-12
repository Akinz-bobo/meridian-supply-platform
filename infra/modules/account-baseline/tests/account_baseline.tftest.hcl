# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed.

mock_provider "aws" {}

variables {
  name            = "meridian-prod-account"
  ebs_kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
  tags = {
    Project = "meridian"
  }
}

run "blocks_public_buckets_for_the_whole_account" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_account_public_access_block.this.block_public_acls,
      aws_s3_account_public_access_block.this.block_public_policy,
      aws_s3_account_public_access_block.this.ignore_public_acls,
      aws_s3_account_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four account-level public access block settings must be on."
  }
}

run "encrypts_new_volumes_with_the_given_key" {
  command = plan

  assert {
    condition     = aws_ebs_encryption_by_default.this.enabled
    error_message = "EBS encryption by default must be on."
  }

  assert {
    condition     = aws_ebs_default_kms_key.this.key_arn == "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
    error_message = "New volumes must use the key that was passed, not the AWS managed key."
  }
}

run "analyses_access_from_outside_the_account" {
  command = plan

  assert {
    condition     = aws_accessanalyzer_analyzer.this.type == "ACCOUNT"
    error_message = "The analyzer's zone of trust is the account."
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.this.analyzer_name == "meridian-prod-account"
    error_message = "The analyzer takes the name it was given."
  }
}

run "requires_long_complex_passwords" {
  command = plan

  assert {
    condition     = aws_iam_account_password_policy.this.minimum_password_length == 14
    error_message = "The default minimum password length is 14."
  }

  assert {
    condition = alltrue([
      aws_iam_account_password_policy.this.require_lowercase_characters,
      aws_iam_account_password_policy.this.require_uppercase_characters,
      aws_iam_account_password_policy.this.require_numbers,
      aws_iam_account_password_policy.this.require_symbols,
    ])
    error_message = "All four character classes must be required."
  }

  assert {
    condition     = aws_iam_account_password_policy.this.password_reuse_prevention == 24
    error_message = "The last 24 passwords may not be reused."
  }
}

run "rejects_a_shorter_minimum_password" {
  command = plan

  variables {
    minimum_password_length = 8
  }

  expect_failures = [var.minimum_password_length]
}

run "rejects_a_key_that_is_not_an_arn" {
  command = plan

  variables {
    ebs_kms_key_arn = "alias/meridian-prod-data"
  }

  expect_failures = [var.ebs_kms_key_arn]
}
