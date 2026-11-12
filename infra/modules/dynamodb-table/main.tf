# A DynamoDB table that is encrypted with a customer managed key and can be
# restored to any second of the last 35 days.
#
# Those two properties are not inputs. What the caller decides is the key
# design, the indexes, whether items expire, whether changes are streamed,
# and how capacity is paid for.

data "aws_region" "current" {}

locals {
  # Built from its parts and not read from the table, so the access
  # policies below are known at plan time and can be policy checked.
  table_arn = "arn:aws:dynamodb:${data.aws_region.current.region}:${var.account_id}:table/${var.name}"

  # Tags for the store itself and not for the resources around it. The
  # classification and anything in store_tags, such as the tag that opts a
  # store in to backups, describe the data and belong on what holds it.
  tags = merge(var.tags, var.store_tags, { DataClassification = var.data_classification })

  provisioned = var.provisioned_capacity != null
  indexes     = { for index in var.global_secondary_indexes : index.name => index }

  # What autoscaling manages when capacity is provisioned: the table, and
  # every index, each with a read and a write dimension.
  scalable = local.provisioned ? merge(
    {
      "table-read"  = { resource = "table/${var.name}", dimension = "dynamodb:table:ReadCapacityUnits", metric = "DynamoDBReadCapacityUtilization", min = var.provisioned_capacity.read_min, max = var.provisioned_capacity.read_max }
      "table-write" = { resource = "table/${var.name}", dimension = "dynamodb:table:WriteCapacityUnits", metric = "DynamoDBWriteCapacityUtilization", min = var.provisioned_capacity.write_min, max = var.provisioned_capacity.write_max }
    },
    { for name, index in local.indexes : "index-${name}-read" => { resource = "table/${var.name}/index/${name}", dimension = "dynamodb:index:ReadCapacityUnits", metric = "DynamoDBReadCapacityUtilization", min = var.provisioned_capacity.read_min, max = var.provisioned_capacity.read_max } },
    { for name, index in local.indexes : "index-${name}-write" => { resource = "table/${var.name}/index/${name}", dimension = "dynamodb:index:WriteCapacityUnits", metric = "DynamoDBWriteCapacityUtilization", min = var.provisioned_capacity.write_min, max = var.provisioned_capacity.write_max } },
  ) : {}
}

resource "aws_dynamodb_table" "this" {
  name      = var.name
  hash_key  = var.hash_key
  range_key = var.range_key

  billing_mode   = local.provisioned ? "PROVISIONED" : "PAY_PER_REQUEST"
  read_capacity  = local.provisioned ? var.provisioned_capacity.read_min : null
  write_capacity = local.provisioned ? var.provisioned_capacity.write_min : null

  deletion_protection_enabled = var.deletion_protection

  # Only the attributes that are part of a key are declared. Everything
  # else in an item is schemaless.
  dynamic "attribute" {
    for_each = var.attributes

    content {
      name = attribute.key
      type = attribute.value
    }
  }

  dynamic "global_secondary_index" {
    for_each = local.indexes

    content {
      name = global_secondary_index.key

      # The index's keys. The provider deprecated hash_key and range_key
      # on indexes in favour of these blocks.
      key_schema {
        attribute_name = global_secondary_index.value.hash_key
        key_type       = "HASH"
      }

      dynamic "key_schema" {
        for_each = global_secondary_index.value.range_key == null ? [] : [global_secondary_index.value.range_key]

        content {
          attribute_name = key_schema.value
          key_type       = "RANGE"
        }
      }

      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.projection_type == "INCLUDE" ? global_secondary_index.value.non_key_attributes : null
      read_capacity      = local.provisioned ? var.provisioned_capacity.read_min : null
      write_capacity     = local.provisioned ? var.provisioned_capacity.write_min : null
    }
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  dynamic "ttl" {
    for_each = var.ttl_attribute == null ? [] : [var.ttl_attribute]

    content {
      enabled        = true
      attribute_name = ttl.value
    }
  }

  stream_enabled   = var.stream_view_type != null
  stream_view_type = var.stream_view_type

  tags = local.tags

  lifecycle {
    # With provisioned capacity, autoscaling changes these after creation.
    # Without this, every plan would try to set them back.
    ignore_changes = [read_capacity, write_capacity]
  }
}

resource "aws_appautoscaling_target" "this" {
  for_each = local.scalable

  service_namespace  = "dynamodb"
  resource_id        = each.value.resource
  scalable_dimension = each.value.dimension
  min_capacity       = each.value.min
  max_capacity       = each.value.max

  tags = var.tags

  depends_on = [aws_dynamodb_table.this]
}

resource "aws_appautoscaling_policy" "this" {
  for_each = local.scalable

  name               = "${var.name}-${each.key}"
  service_namespace  = "dynamodb"
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value = var.provisioned_capacity.target_utilization

    predefined_metric_specification {
      predefined_metric_type = each.value.metric
    }
  }
}

# Policies for the roles that use the table. A service attaches one of
# these to its workload role instead of writing its own.

data "aws_iam_policy_document" "read" {
  statement {
    sid = "ReadItems"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:ConditionCheckItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [
      local.table_arn,
      "${local.table_arn}/index/*",
    ]
  }

  statement {
    sid       = "DecryptItems"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]

    # Only by way of DynamoDB, and only for this table.
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:dynamodb:tableName"
      values   = [var.name]
    }
  }
}

# A transaction needs no action of its own. DynamoDB authorises
# TransactWriteItems by the item actions inside it: PutItem, UpdateItem,
# DeleteItem and ConditionCheckItem.
data "aws_iam_policy_document" "write" {
  source_policy_documents = [data.aws_iam_policy_document.read.json]

  statement {
    sid = "WriteItems"
    actions = [
      "dynamodb:BatchWriteItem",
      "dynamodb:DeleteItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [local.table_arn]
  }

  statement {
    sid       = "EncryptItems"
    actions   = ["kms:GenerateDataKey"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:dynamodb:tableName"
      values   = [var.name]
    }
  }
}

# For a table that is a record and must not be rewritten: items can be
# added and read, and never changed or removed. Whether an item may replace
# an existing one is up to the writer's condition expression, and a ledger
# writes with attribute_not_exists.
data "aws_iam_policy_document" "append" {
  source_policy_documents = [data.aws_iam_policy_document.read.json]

  statement {
    sid       = "AddItems"
    actions   = ["dynamodb:PutItem"]
    resources = [local.table_arn]
  }

  statement {
    sid       = "EncryptItems"
    actions   = ["kms:GenerateDataKey"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:dynamodb:tableName"
      values   = [var.name]
    }
  }
}

data "aws_iam_policy_document" "stream" {
  statement {
    sid = "ReadTheChangeStream"
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
    ]
    resources = ["${local.table_arn}/stream/*"]
  }

  statement {
    sid       = "ListStreams"
    actions   = ["dynamodb:ListStreams"]
    resources = [local.table_arn]
  }

  statement {
    sid       = "DecryptStreamRecords"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:dynamodb:tableName"
      values   = [var.name]
    }
  }
}
