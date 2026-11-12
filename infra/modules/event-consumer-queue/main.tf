# Everything one consumer needs to receive one kind of event: a queue, its
# dead-letter queue, the rule on the bus that feeds it, and an alarm.
#
# The consumer reads from the queue and never from the bus. The queue gives
# it buffering when it is slow or down, retries when it fails, and
# isolation: another consumer's backlog or poison message is not its
# problem. A message that fails repeatedly is moved aside to the
# dead-letter queue, where it raises an alarm and waits to be looked at.
# Nothing is dropped silently.

data "aws_region" "current" {}

locals {
  ra        = "${data.aws_region.current.region}:${var.account_id}"
  queue_arn = "arn:aws:sqs:${local.ra}:${var.name}"
  dlq_name  = "${var.name}-dlq"
  dlq_arn   = "arn:aws:sqs:${local.ra}:${local.dlq_name}"
  rule_arn  = "arn:aws:events:${local.ra}:rule/${var.bus_name}/${var.name}"

  # Events of the given types, from any service of the platform.
  pattern = jsonencode({
    "detail-type" = sort(tolist(var.event_types))
    source        = [{ prefix = "${var.source_prefix}." }]
  })
}

resource "aws_sqs_queue" "dead_letter" {
  name = local.dlq_name

  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  # Long enough to survive a weekend and the investigation after it.
  message_retention_seconds = var.dead_letter_retention_days * 86400

  tags = var.tags
}

resource "aws_sqs_queue" "this" {
  name = var.name

  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.retention_days * 86400

  # Wait for a message instead of returning empty at once. Fewer calls,
  # lower cost, and messages arrive just as fast.
  receive_wait_time_seconds = 20

  # The ARN is built from the name so that the policy is known at plan
  # time. The dependency below keeps the order: the dead-letter queue must
  # exist before a queue can point at it.
  redrive_policy = jsonencode({
    deadLetterTargetArn = local.dlq_arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = var.tags

  depends_on = [aws_sqs_queue.dead_letter]
}

# Only this queue may use this dead-letter queue.
resource "aws_sqs_queue_redrive_allow_policy" "dead_letter" {
  queue_url = aws_sqs_queue.dead_letter.id

  depends_on = [aws_sqs_queue.this]

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [local.queue_arn]
  })
}

data "aws_iam_policy_document" "queue" {
  # The bus may deliver, and only through this module's rule. No other
  # rule, and nothing that is not EventBridge, can put a message here.
  statement {
    sid       = "TheRuleDeliversEvents"
    actions   = ["sqs:SendMessage"]
    resources = [local.queue_arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [local.rule_arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [local.queue_arn]

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
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id
  policy    = data.aws_iam_policy_document.queue.json
}

data "aws_iam_policy_document" "dead_letter" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [local.dlq_arn]

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
}

resource "aws_sqs_queue_policy" "dead_letter" {
  queue_url = aws_sqs_queue.dead_letter.id
  policy    = data.aws_iam_policy_document.dead_letter.json
}

resource "aws_cloudwatch_event_rule" "this" {
  name           = var.name
  description    = "Delivers ${join(", ", sort(tolist(var.event_types)))} to the queue ${var.name}."
  event_bus_name = var.bus_name
  event_pattern  = local.pattern

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "this" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = var.bus_name
  target_id      = "queue"
  arn            = aws_sqs_queue.this.arn

  # The consumer receives the envelope, which is the event's detail. The
  # wrapper EventBridge adds around it is of no use to a consumer.
  input_path = "$.detail"

  depends_on = [aws_sqs_queue_policy.this]
}

# One message in a dead-letter queue is a failure someone must look at.
resource "aws_cloudwatch_metric_alarm" "dead_letter" {
  alarm_name        = "${var.name}-dlq-not-empty"
  alarm_description = "A message for ${var.name} failed ${var.max_receive_count} times and was moved to its dead-letter queue. See docs/runbooks/dead-letter-queue.md."

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  dimensions  = { QueueName = aws_sqs_queue.dead_letter.name }
  statistic   = "Maximum"

  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0

  # No data means the queue is empty, which is the healthy state.
  treat_missing_data = "notBreaching"

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = var.tags
}

# What the consumer's role needs.
data "aws_iam_policy_document" "consume" {
  statement {
    sid = "ReceiveAndAcknowledge"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [local.queue_arn]
  }

  statement {
    sid       = "DecryptMessages"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sqs.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}
