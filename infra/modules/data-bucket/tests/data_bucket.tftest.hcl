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
  name                = "meridian-prod-catalog-uploads-333333333333-eu-west-1"
  data_classification = "confidential"
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
  tags = {
    Project = "meridian"
  }
}

run "blocks_every_form_of_public_access" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be on."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled."
  }
}

run "keeps_previous_versions" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_versioning.this.versioning_configuration).status == "Enabled"
    error_message = "Versioning must be enabled."
  }
}

run "encrypts_with_the_given_key_and_a_bucket_key" {
  command = plan

  assert {
    condition = one([
      for rule in aws_s3_bucket_server_side_encryption_configuration.this.rule :
      one(rule.apply_server_side_encryption_by_default).kms_master_key_id
    ]) == "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
    error_message = "Default encryption must use the key that was passed."
  }

  assert {
    condition     = one([for rule in aws_s3_bucket_server_side_encryption_configuration.this.rule : rule.bucket_key_enabled])
    error_message = "The bucket key must be on, to limit KMS calls."
  }
}

run "carries_its_classification_as_a_tag" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.tags["DataClassification"] == "confidential"
    error_message = "The classification must become the DataClassification tag."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Project"] == "meridian"
    error_message = "The caller's tags must be kept."
  }
}

run "refuses_requests_without_tls" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.bucket.json).Statement : statement
      if statement.Sid == "DenyInsecureTransport"
    ]).Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The bucket policy must deny requests that do not use TLS."
  }
}

run "refuses_uploads_under_another_key" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.bucket.json).Statement : statement
      if statement.Sid == "DenyUploadsWithAnotherKey"
    ]).Condition.StringNotEqualsIfExists["s3:x-amz-server-side-encryption-aws-kms-key-id"] == "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
    error_message = "An upload that names a key other than the bucket's must be denied."
  }
}

run "is_not_emptied_on_destroy_by_default" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must default to off."
  }
}

run "keeps_old_versions_for_ninety_days_and_objects_indefinitely_by_default" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration).noncurrent_days == 90
    error_message = "Old versions are kept for 90 days by default."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule[0].expiration) == 0
    error_message = "Objects must not expire unless expiration_days is set."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload).days_after_initiation == 7
    error_message = "Unfinished uploads must be cleaned up after 7 days."
  }
}

run "applies_retention_and_storage_transitions" {
  command = plan

  variables {
    expiration_days = 2555
    transitions = [
      { days = 90, storage_class = "STANDARD_IA" },
      { days = 365, storage_class = "GLACIER_IR" },
    ]
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule[0].expiration).days == 2555
    error_message = "expiration_days must reach the lifecycle rule."
  }

  assert {
    condition     = toset([for transition in aws_s3_bucket_lifecycle_configuration.this.rule[0].transition : transition.storage_class]) == toset(["STANDARD_IA", "GLACIER_IR"])
    error_message = "Both transitions must reach the lifecycle rule."
  }
}

run "sends_events_only_when_asked" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_notification.this) == 0
    error_message = "Notifications are off by default."
  }
}

run "can_send_events_to_eventbridge" {
  command = plan

  variables {
    eventbridge_notifications = true
  }

  assert {
    condition     = aws_s3_bucket_notification.this[0].eventbridge
    error_message = "eventbridge_notifications must turn on EventBridge delivery."
  }
}

run "the_read_policy_reads_this_bucket_and_nothing_else" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.read_policy_json).Statement : [
        for resource in flatten([statement.Resource]) :
        startswith(resource, "arn:aws:s3:::meridian-prod-catalog-uploads-333333333333-eu-west-1") || resource == "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
      ]
    ]))
    error_message = "The read policy names a resource other than this bucket and its key."
  }

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.read_policy_json).Statement : [
        for action in flatten([statement.Action]) : !can(regex(":(Put|Delete|Abort)", action)) && !strcontains(action, "*")
      ]
    ]))
    error_message = "The read policy must contain exact read actions only."
  }
}

run "the_key_is_usable_only_for_objects_in_this_bucket" {
  command = plan

  assert {
    condition = alltrue([
      for statement in jsondecode(output.write_policy_json).Statement :
      contains(flatten([statement.Condition.StringLike["kms:EncryptionContext:aws:s3:arn"]]), "arn:aws:s3:::meridian-prod-catalog-uploads-333333333333-eu-west-1/*")
      if startswith(flatten([statement.Action])[0], "kms:")
    ])
    error_message = "Every key statement must be tied to this bucket through the encryption context."
  }
}

run "the_write_policy_cannot_delete_versions_or_change_the_bucket" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.write_policy_json).Statement : [
        for action in flatten([statement.Action]) :
        !contains(["s3:DeleteObjectVersion", "s3:PutBucketPolicy", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration", "s3:DeleteBucket", "s3:PutObjectAcl"], action) && !strcontains(action, "*")
      ]
    ]))
    error_message = "The write policy must not allow deleting versions or changing how the bucket is configured."
  }
}

run "rejects_an_unknown_classification" {
  command = plan

  variables {
    data_classification = "secret"
  }

  expect_failures = [var.data_classification]
}

run "rejects_a_bucket_without_a_customer_managed_key" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_a_name_with_dots_or_upper_case" {
  command = plan

  variables {
    name = "Meridian.Prod.Uploads"
  }

  expect_failures = [var.name]
}

run "rejects_an_early_move_to_infrequent_access" {
  command = plan

  variables {
    transitions = [{ days = 7, storage_class = "STANDARD_IA" }]
  }

  expect_failures = [var.transitions]
}

run "rejects_an_unknown_storage_class" {
  command = plan

  variables {
    transitions = [{ days = 90, storage_class = "COLD" }]
  }

  expect_failures = [var.transitions]
}

run "rejects_almost_no_version_retention" {
  command = plan

  variables {
    noncurrent_version_retention_days = 1
  }

  expect_failures = [var.noncurrent_version_retention_days]
}
