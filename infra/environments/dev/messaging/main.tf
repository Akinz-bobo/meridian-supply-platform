# Messaging layer: how services tell each other what happened.
#
# The bus, the consumer queues, the notification topics and the movement
# stream. It is applied after the data layer and reads what it needs from
# Parameter Store. See docs/architecture/messaging.md.

module "context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "events"
}

locals {
  foundation = "/${var.project}/${var.environment}"

  # Facts published by the foundation layer, by short name.
  foundation_parameters = {
    messaging_key_arn     = "security/kms/messaging-key-arn"
    logs_key_arn          = "security/kms/logs-key-arn"
    workload_boundary_arn = "security/iam/workload-boundary-arn"
  }

  # Every service that publishes events, by the name used in its source.
  # The event catalogue in docs/architecture/events.md lists what each
  # publishes.
  publishers = ["budget", "catalog", "curation", "erp-gateway", "inventory", "planning", "procurement"]
}

data "aws_ssm_parameter" "foundation" {
  for_each = local.foundation_parameters

  name = "${local.foundation}/${each.value}"
}

locals {
  # nonsensitive: these are identifiers, stored as plain String parameters.
  facts = { for name, parameter in data.aws_ssm_parameter.foundation : name => nonsensitive(parameter.value) }
}

module "event_bus" {
  source = "../../../modules/event-bus"

  name = module.context.prefix
  tags = module.context.tags

  account_id    = var.aws_account_id
  source_prefix = var.project
  publishers    = local.publishers

  kms_key_arn        = local.facts.messaging_key_arn
  logs_kms_key_arn   = local.facts.logs_key_arn
  log_retention_days = var.log_retention_days

  # The emulator can create a CloudWatch Logs resource policy and cannot
  # delete one, which would make the layer impossible to tear down there.
  # See emulator difference 26.
  manage_log_resource_policy = var.aws_endpoint_url == null
}

resource "aws_ssm_parameter" "event_bus" {
  for_each = {
    "bus-name"       = module.event_bus.bus_name
    "bus-arn"        = module.event_bus.bus_arn
    "archive-arn"    = module.event_bus.archive_arn
    "log-group-name" = module.event_bus.log_group_name
  }

  name        = "${module.context.ssm_path}/${each.key}"
  description = "Event bus fact, published by the messaging layer."
  type        = "String"
  value       = each.value

  tags = module.context.tags
}
