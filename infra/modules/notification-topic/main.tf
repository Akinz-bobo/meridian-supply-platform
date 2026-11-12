# An SNS topic for telling people, or their tools, that something happened.
#
# The topic is encrypted, refuses requests without TLS, and accepts
# messages only from the AWS services named by the caller, acting for this
# account. Roles that need to publish get a policy from the output.

data "aws_region" "current" {}

locals {
  topic_arn = "arn:aws:sns:${data.aws_region.current.region}:${var.account_id}:${var.name}"
}

resource "aws_sns_topic" "this" {
  name              = var.name
  display_name      = var.display_name
  kms_master_key_id = var.kms_key_arn

  tags = var.tags
}

data "aws_iam_policy_document" "topic" {
  # CloudWatch alarms and EventBridge rules publish as the service, not as
  # a role, so they are admitted here. Each is limited to this account.
  dynamic "statement" {
    for_each = length(var.publishing_services) > 0 ? [1] : []

    content {
      sid       = "NamedServicesPublishForThisAccount"
      actions   = ["sns:Publish"]
      resources = [local.topic_arn]

      principals {
        type        = "Service"
        identifiers = sort(tolist(var.publishing_services))
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [var.account_id]
      }
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sns:Publish"]
    resources = [local.topic_arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # A subscription decides where messages go. Only this account may add one.
  statement {
    sid       = "OnlyThisAccountSubscribes"
    effect    = "Deny"
    actions   = ["sns:Subscribe", "sns:Receive"]
    resources = [local.topic_arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "this" {
  arn    = aws_sns_topic.this.arn
  policy = data.aws_iam_policy_document.topic.json
}

resource "aws_sns_topic_subscription" "this" {
  for_each = var.subscriptions

  topic_arn = aws_sns_topic.this.arn
  protocol  = each.value.protocol
  endpoint  = each.value.endpoint

  # Deliver the message as it was published, without the SNS wrapper, to
  # endpoints that can take it.
  raw_message_delivery = contains(["sqs", "https", "firehose"], each.value.protocol) ? each.value.raw_message_delivery : null
}

# What a role needs in order to publish.
data "aws_iam_policy_document" "publish" {
  statement {
    sid       = "PublishToThisTopic"
    actions   = ["sns:Publish"]
    resources = [local.topic_arn]
  }

  statement {
    sid       = "EncryptMessages"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sns.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}
