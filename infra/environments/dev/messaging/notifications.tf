# Topics: where alarms go, and where events that exist to tell a person
# something go. Who is subscribed is an operational decision made per
# environment, and is not in this repository. See docs/architecture/messaging.md.

module "alarms_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "alarms"
}

# Every alarm in the environment notifies this topic.
module "alarms_topic" {
  source = "../../../modules/notification-topic"

  name         = module.alarms_context.prefix
  tags         = module.alarms_context.tags
  display_name = "Meridian ${var.environment} alarms"
  account_id   = var.aws_account_id

  kms_key_arn         = local.facts.messaging_key_arn
  publishing_services = ["cloudwatch.amazonaws.com"]

  # Who is told. Set per environment in env.tfvars. With none, alarms are
  # raised and reach nobody, which is tracked as a review finding.
  subscriptions = var.alarm_subscriptions
}

module "notifications_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "notifications"
}

# Events whose purpose is to tell someone: a batch about to expire, a
# budget exceeded, an order waiting for approval.
module "notifications_topic" {
  source = "../../../modules/notification-topic"

  name         = module.notifications_context.prefix
  tags         = module.notifications_context.tags
  display_name = "Meridian ${var.environment}"
  account_id   = var.aws_account_id

  kms_key_arn         = local.facts.messaging_key_arn
  publishing_services = ["events.amazonaws.com"]
}

locals {
  # From the event catalogue: the events consumed by "Notifications".
  notification_events = [
    "ApprovalRequested",
    "BatchExpired",
    "BatchRecalled",
    "BatchShortDated",
    "BudgetExceeded",
    "ReplenishmentProposed",
    "StockDiscrepancyDetected",
  ]
}

resource "aws_cloudwatch_event_rule" "notifications" {
  name           = module.notifications_context.prefix
  description    = "Sends the events that exist to tell a person something to the notifications topic."
  event_bus_name = module.event_bus.bus_name

  event_pattern = jsonencode({
    "detail-type" = local.notification_events
    source        = [{ prefix = "${var.project}." }]
  })

  tags = module.notifications_context.tags
}

resource "aws_cloudwatch_event_target" "notifications" {
  rule           = aws_cloudwatch_event_rule.notifications.name
  event_bus_name = module.event_bus.bus_name
  target_id      = "topic"
  arn            = module.notifications_topic.topic_arn

  # Subscribers receive the envelope, as queue consumers do.
  input_path = "$.detail"
}

resource "aws_ssm_parameter" "topics" {
  for_each = {
    "${module.alarms_context.ssm_path}/topic-arn"        = module.alarms_topic.topic_arn
    "${module.notifications_context.ssm_path}/topic-arn" = module.notifications_topic.topic_arn
  }

  name        = each.key
  description = "Topic published by the messaging layer."
  type        = "String"
  value       = each.value

  tags = module.context.tags
}
