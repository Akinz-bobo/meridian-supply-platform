# The bus that carries business events between services.
#
# Producers put events on the bus and do not know who consumes them. Each
# producer may publish only under its own source name, so one service
# cannot forge another's events. Every event is archived for replay and
# written to a log group, so that "was it published, and what did it say"
# can always be answered.

data "aws_region" "current" {}

locals {
  ra      = "${data.aws_region.current.region}:${var.account_id}"
  bus_arn = "arn:aws:events:${local.ra}:event-bus/${var.name}"

  # EventBridge only delivers to log groups under this path.
  log_group_name = "/aws/events/${var.name}"

  # Every event of the platform: any source that starts with the prefix.
  all_events = jsonencode({ source = [{ prefix = "${var.source_prefix}." }] })
}

resource "aws_cloudwatch_event_bus" "this" {
  name               = var.name
  description        = var.description
  kms_key_identifier = var.kms_key_arn

  tags = var.tags
}

# IAM decides who in the account may publish. This closes the other door:
# nothing outside the account can be given access to the bus, by anyone.
data "aws_iam_policy_document" "bus" {
  statement {
    sid       = "OnlyThisAccountPublishes"
    effect    = "Deny"
    actions   = ["events:PutEvents"]
    resources = [local.bus_arn]

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

resource "aws_cloudwatch_event_bus_policy" "this" {
  event_bus_name = aws_cloudwatch_event_bus.this.name
  policy         = data.aws_iam_policy_document.bus.json
}

# Events are kept so that a consumer added later, or one that lost data,
# can be sent the past again.
resource "aws_cloudwatch_event_archive" "this" {
  name             = var.name
  description      = "Every event on ${var.name}, kept for replay."
  event_source_arn = aws_cloudwatch_event_bus.this.arn
  event_pattern    = local.all_events
  retention_days   = var.archive_retention_days
}

# A readable record of every event, for answering questions during an
# incident without replaying anything.
resource "aws_cloudwatch_log_group" "events" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

data "aws_iam_policy_document" "log_delivery" {
  statement {
    sid       = "EventBridgeWritesEventsToTheLog"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${local.ra}:log-group:${local.log_group_name}:*"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "events" {
  policy_name     = "${var.name}-event-log"
  policy_document = data.aws_iam_policy_document.log_delivery.json
}

resource "aws_cloudwatch_event_rule" "log" {
  name           = "${var.name}-log-all"
  description    = "Writes every event to the log group."
  event_bus_name = aws_cloudwatch_event_bus.this.name
  event_pattern  = local.all_events

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "log" {
  rule           = aws_cloudwatch_event_rule.log.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  target_id      = "log"
  arn            = aws_cloudwatch_log_group.events.arn

  depends_on = [aws_cloudwatch_log_resource_policy.events]
}

# What a producer's role needs. One policy per publisher, each limited to
# its own source name.
data "aws_iam_policy_document" "publish" {
  for_each = var.publishers

  statement {
    sid       = "PublishAsThisServiceOnly"
    actions   = ["events:PutEvents"]
    resources = [local.bus_arn]

    condition {
      test     = "StringEquals"
      variable = "events:source"
      values   = ["${var.source_prefix}.${each.key}"]
    }
  }

  # The bus is encrypted, so a publisher needs a data key from its key.
  statement {
    sid       = "EncryptEventsOnTheBus"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["events.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}
