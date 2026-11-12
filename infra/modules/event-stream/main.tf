# A Kinesis stream: an ordered, replayable log of records.
#
# Records with the same partition key go to the same shard and are read in
# the order they were written, which a queue or the event bus does not
# promise. Several readers can read the same records independently, and
# each can go back and read them again within the retention period.
#
# The stream is always encrypted with a customer managed key. Producers and
# consumers get separate policies: a producer cannot read, and a consumer
# cannot write.

data "aws_region" "current" {}

locals {
  stream_arn = "arn:aws:kinesis:${data.aws_region.current.region}:${var.account_id}:stream/${var.name}"

  tags = merge(var.tags, { DataClassification = var.data_classification })

  provisioned = var.shard_count != null
}

resource "aws_kinesis_stream" "this" {
  name = var.name

  # On demand, the stream scales its own shards with traffic. With a shard
  # count, capacity is fixed and paid for whether used or not.
  shard_count = var.shard_count

  stream_mode_details {
    stream_mode = local.provisioned ? "PROVISIONED" : "ON_DEMAND"
  }

  retention_period = var.retention_hours

  encryption_type = "KMS"
  kms_key_id      = var.kms_key_arn

  # Metrics per shard show a hot shard, which the stream-level average
  # hides. A hot shard means one partition key carries too much.
  shard_level_metrics = [
    "IncomingBytes",
    "IncomingRecords",
    "IteratorAgeMilliseconds",
    "ReadProvisionedThroughputExceeded",
    "WriteProvisionedThroughputExceeded",
  ]

  tags = local.tags
}

data "aws_iam_policy_document" "produce" {
  statement {
    sid = "WriteRecords"
    actions = [
      "kinesis:DescribeStreamSummary",
      "kinesis:ListShards",
      "kinesis:PutRecord",
      "kinesis:PutRecords",
    ]
    resources = [local.stream_arn]
  }

  statement {
    sid       = "EncryptRecords"
    actions   = ["kms:GenerateDataKey"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:kinesis:arn"
      values   = [local.stream_arn]
    }
  }
}

data "aws_iam_policy_document" "consume" {
  statement {
    sid = "ReadRecords"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards",
    ]
    resources = [local.stream_arn]
  }

  statement {
    sid       = "DecryptRecords"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:kinesis:arn"
      values   = [local.stream_arn]
    }
  }
}
