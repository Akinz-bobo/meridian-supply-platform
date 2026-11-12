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
  name                = "meridian-prod-inventory-movement-stream"
  account_id          = "333333333333"
  data_classification = "internal"
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"
  tags = {
    Project = "meridian"
  }
}

run "is_always_encrypted_with_the_given_key" {
  command = plan

  assert {
    condition     = aws_kinesis_stream.this.encryption_type == "KMS" && aws_kinesis_stream.this.kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"
    error_message = "The stream must be encrypted with the key that was passed."
  }
}

run "scales_itself_by_default" {
  command = plan

  assert {
    condition     = one(aws_kinesis_stream.this.stream_mode_details).stream_mode == "ON_DEMAND"
    error_message = "The default is an on-demand stream."
  }
}

run "can_have_fixed_capacity" {
  command = plan

  variables {
    shard_count = 4
  }

  assert {
    condition     = one(aws_kinesis_stream.this.stream_mode_details).stream_mode == "PROVISIONED" && aws_kinesis_stream.this.shard_count == 4
    error_message = "A shard count switches the stream to provisioned capacity."
  }
}

run "keeps_records_for_two_days_by_default" {
  command = plan

  assert {
    condition     = aws_kinesis_stream.this.retention_period == 48
    error_message = "Records are readable for 48 hours by default."
  }
}

run "reports_metrics_per_shard" {
  command = plan

  assert {
    condition     = contains(aws_kinesis_stream.this.shard_level_metrics, "IteratorAgeMilliseconds") && contains(aws_kinesis_stream.this.shard_level_metrics, "WriteProvisionedThroughputExceeded")
    error_message = "Consumer lag and write throttling must be reported per shard."
  }
}

run "carries_its_classification_as_a_tag" {
  command = plan

  assert {
    condition     = aws_kinesis_stream.this.tags["DataClassification"] == "internal"
    error_message = "The classification must become the DataClassification tag."
  }
}

run "a_producer_can_write_and_not_read" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.produce_policy_json).Statement : [
        for action in flatten([statement.Action]) :
        !contains(["kinesis:GetRecords", "kinesis:GetShardIterator", "kms:Decrypt"], action) && !strcontains(action, "*")
      ]
    ]))
    error_message = "A producer must not be able to read records or decrypt them."
  }
}

run "a_consumer_can_read_and_not_write" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.consume_policy_json).Statement : [
        for action in flatten([statement.Action]) :
        !contains(["kinesis:PutRecord", "kinesis:PutRecords", "kms:GenerateDataKey", "kinesis:DeleteStream"], action) && !strcontains(action, "*")
      ]
    ]))
    error_message = "A consumer must not be able to write records or delete the stream."
  }
}

run "the_policies_name_this_stream_and_the_key_is_tied_to_it" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for document in [output.produce_policy_json, output.consume_policy_json] : [
        for statement in jsondecode(document).Statement :
        startswith(flatten([statement.Action])[0], "kms:")
        ? statement.Condition.StringEquals["kms:EncryptionContext:aws:kinesis:arn"] == "arn:aws:kinesis:eu-west-1:333333333333:stream/meridian-prod-inventory-movement-stream"
        : statement.Resource == "arn:aws:kinesis:eu-west-1:333333333333:stream/meridian-prod-inventory-movement-stream"
      ]
    ]))
    error_message = "Each statement names this stream, and use of the key is tied to it through the encryption context."
  }
}

run "rejects_retention_shorter_than_a_day" {
  command = plan

  variables {
    retention_hours = 6
  }

  expect_failures = [var.retention_hours]
}

run "rejects_a_stream_without_a_customer_managed_key" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_an_unknown_classification" {
  command = plan

  variables {
    data_classification = "secret"
  }

  expect_failures = [var.data_classification]
}

run "rejects_zero_shards" {
  command = plan

  variables {
    shard_count = 0
  }

  expect_failures = [var.shard_count]
}
