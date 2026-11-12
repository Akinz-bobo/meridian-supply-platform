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
  name                = "meridian-prod-inventory-movements"
  account_id          = "333333333333"
  data_classification = "internal"
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
  hash_key            = "pk"
  range_key           = "sk"
  attributes = {
    pk = "S"
    sk = "S"
  }
  tags = {
    Project = "meridian"
  }
}

run "can_always_be_restored_to_a_point_in_time" {
  command = plan

  assert {
    condition     = one(aws_dynamodb_table.this.point_in_time_recovery).enabled
    error_message = "Point-in-time recovery must be on."
  }
}

run "is_encrypted_with_the_given_key" {
  command = plan

  assert {
    condition     = one(aws_dynamodb_table.this.server_side_encryption).enabled && one(aws_dynamodb_table.this.server_side_encryption).kms_key_arn == "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
    error_message = "The table must be encrypted with the key that was passed."
  }
}

run "cannot_be_deleted_by_default" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled
    error_message = "Deletion protection must default to on."
  }
}

run "is_billed_per_request_by_default" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST"
    error_message = "The default billing mode is on demand."
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 0
    error_message = "On demand tables have no autoscaling."
  }
}

run "carries_its_classification_as_a_tag" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.tags["DataClassification"] == "internal"
    error_message = "The classification must become the DataClassification tag."
  }
}

run "has_no_stream_unless_asked" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.stream_enabled == false
    error_message = "Streams are off by default."
  }
}

run "streams_changes_and_expires_items_when_asked" {
  command = plan

  variables {
    stream_view_type = "NEW_IMAGE"
    ttl_attribute    = "expires_at"
  }

  assert {
    condition     = aws_dynamodb_table.this.stream_enabled && aws_dynamodb_table.this.stream_view_type == "NEW_IMAGE"
    error_message = "stream_view_type must turn the stream on."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.ttl).attribute_name == "expires_at"
    error_message = "ttl_attribute must reach the table."
  }
}

run "adds_indexes_for_further_access_patterns" {
  command = plan

  variables {
    attributes = {
      pk     = "S"
      sk     = "S"
      gsi1pk = "S"
      gsi1sk = "S"
    }
    global_secondary_indexes = [
      { name = "by-warehouse-day", hash_key = "gsi1pk", range_key = "gsi1sk" },
    ]
  }

  assert {
    condition     = one(aws_dynamodb_table.this.global_secondary_index).name == "by-warehouse-day"
    error_message = "The index must be created."
  }

  assert {
    condition     = [for key in one(aws_dynamodb_table.this.global_secondary_index).key_schema : "${key.key_type}:${key.attribute_name}"] == ["HASH:gsi1pk", "RANGE:gsi1sk"]
    error_message = "The index must have its partition key and then its sort key."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.global_secondary_index).projection_type == "ALL"
    error_message = "An index projects all attributes by default."
  }
}

run "autoscales_the_table_and_every_index_when_capacity_is_provisioned" {
  command = plan

  variables {
    attributes = {
      pk     = "S"
      sk     = "S"
      gsi1pk = "S"
    }
    global_secondary_indexes = [
      { name = "by-batch", hash_key = "gsi1pk" },
    ]
    provisioned_capacity = {
      read_min  = 5
      read_max  = 100
      write_min = 5
      write_max = 400
    }
  }

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PROVISIONED"
    error_message = "provisioned_capacity must switch the billing mode."
  }

  assert {
    condition     = toset(keys(aws_appautoscaling_target.this)) == toset(["table-read", "table-write", "index-by-batch-read", "index-by-batch-write"])
    error_message = "The table and each index need a read and a write scaling target."
  }

  assert {
    condition     = aws_appautoscaling_target.this["table-write"].max_capacity == 400 && aws_appautoscaling_target.this["table-write"].min_capacity == 5
    error_message = "Scaling limits must come from provisioned_capacity."
  }

  assert {
    condition     = one(aws_appautoscaling_policy.this["table-read"].target_tracking_scaling_policy_configuration).target_value == 70
    error_message = "The default utilisation target is 70 percent."
  }
}

run "the_read_policy_cannot_scan_or_write" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.read_policy_json).Statement : [
        for action in flatten([statement.Action]) :
        !contains(["dynamodb:Scan", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:UpdateItem"], action) && !strcontains(action, "*")
      ]
    ]))
    error_message = "The read policy must not include Scan or any write, and must list actions exactly."
  }
}

run "the_policies_name_this_table_and_nothing_else" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for document in [output.read_policy_json, output.write_policy_json, output.stream_policy_json] : [
        for statement in jsondecode(document).Statement : [
          for resource in flatten([statement.Resource]) :
          startswith(resource, "arn:aws:dynamodb:eu-west-1:333333333333:table/meridian-prod-inventory-movements") || resource == "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
        ]
      ]
    ]))
    error_message = "A policy names a resource other than this table and its key."
  }
}

run "the_write_policy_cannot_change_or_delete_the_table" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.write_policy_json).Statement : [
        for action in flatten([statement.Action]) :
        !contains(["dynamodb:DeleteTable", "dynamodb:UpdateTable", "dynamodb:CreateTable", "dynamodb:UpdateContinuousBackups", "dynamodb:Scan"], action)
      ]
    ]))
    error_message = "The write policy is for items. It must not manage the table."
  }
}

run "the_key_is_usable_only_for_this_table" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for document in [output.read_policy_json, output.write_policy_json, output.stream_policy_json] : [
        for statement in jsondecode(document).Statement :
        statement.Condition.StringEquals["kms:EncryptionContext:aws:dynamodb:tableName"] == "meridian-prod-inventory-movements"
        if startswith(flatten([statement.Action])[0], "kms:")
      ]
    ]))
    error_message = "Every key statement must be tied to this table through the encryption context."
  }
}

run "rejects_a_key_whose_type_is_not_declared" {
  command = plan

  variables {
    range_key = "created_at"
  }

  expect_failures = [var.attributes]
}

run "rejects_a_declared_attribute_that_is_not_a_key" {
  command = plan

  variables {
    attributes = {
      pk       = "S"
      sk       = "S"
      quantity = "N"
    }
  }

  expect_failures = [var.attributes]
}

run "rejects_an_unknown_attribute_type" {
  command = plan

  variables {
    attributes = {
      pk = "STRING"
      sk = "S"
    }
  }

  expect_failures = [var.attributes]
}

run "rejects_an_include_projection_with_nothing_to_include" {
  command = plan

  variables {
    attributes = {
      pk     = "S"
      sk     = "S"
      gsi1pk = "S"
    }
    global_secondary_indexes = [
      { name = "by-batch", hash_key = "gsi1pk", projection_type = "INCLUDE" },
    ]
  }

  expect_failures = [var.global_secondary_indexes]
}

run "rejects_a_minimum_above_its_maximum" {
  command = plan

  variables {
    provisioned_capacity = {
      read_min  = 50
      read_max  = 10
      write_min = 5
      write_max = 10
    }
  }

  expect_failures = [var.provisioned_capacity]
}

run "rejects_an_unknown_stream_view" {
  command = plan

  variables {
    stream_view_type = "EVERYTHING"
  }

  expect_failures = [var.stream_view_type]
}

run "rejects_a_table_without_a_customer_managed_key" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_an_unknown_classification" {
  command = plan

  variables {
    data_classification = "private"
  }

  expect_failures = [var.data_classification]
}

run "puts_store_tags_on_the_table" {
  command = plan

  variables {
    store_tags = { Backup = "daily" }
  }

  assert {
    condition     = aws_dynamodb_table.this.tags["Backup"] == "daily" && aws_dynamodb_table.this.tags["DataClassification"] == "internal"
    error_message = "A store tag must reach the table, alongside its classification."
  }
}
