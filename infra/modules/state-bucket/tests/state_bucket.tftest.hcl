# Plan-only tests against a mocked provider. They need no AWS account and no
# emulator, and they fail if a protection on the state bucket is removed.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name = "meridian-shared-tfstate-444444444444-eu-west-1"
  tags = {
    Project = "meridian"
  }
}

run "blocks_every_form_of_public_access" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be on."
  }
}

run "versions_state_so_it_can_be_rolled_back" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled on the state bucket."
  }
}

run "encrypts_with_a_customer_managed_key_that_rotates" {
  command = plan

  assert {
    condition = one([
      for rule in aws_s3_bucket_server_side_encryption_configuration.state.rule :
      one(rule.apply_server_side_encryption_by_default).sse_algorithm
    ]) == "aws:kms"
    error_message = "State must be encrypted with KMS, not the S3 managed default."
  }

  assert {
    condition     = aws_kms_key.state.enable_key_rotation
    error_message = "The state key must rotate."
  }
}

run "disables_acls" {
  command = plan

  assert {
    condition     = aws_s3_bucket_ownership_controls.state.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled on the state bucket."
  }
}

run "refuses_to_be_destroyed_with_state_in_it_by_default" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.force_destroy == false
    error_message = "force_destroy must default to false."
  }
}

run "keeps_old_versions_for_the_configured_time" {
  command = plan

  variables {
    noncurrent_version_retention_days = 120
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.state.rule[0].noncurrent_version_expiration[0].noncurrent_days == 120
    error_message = "The retention setting was not applied."
  }
}

run "rejects_a_retention_too_short_to_recover_from" {
  command = plan

  variables {
    noncurrent_version_retention_days = 7
  }

  expect_failures = [var.noncurrent_version_retention_days]
}
