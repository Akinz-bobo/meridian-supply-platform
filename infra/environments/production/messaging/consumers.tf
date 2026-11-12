# Consumer queues: one per consuming service per event it is interested in.
#
# The event catalogue in docs/architecture/events.md says who consumes
# what. A queue is added here when its consumer is about to be built, and
# these three exist to carry the first end-to-end flows: a product reaching
# inventory, and a delivery reaching both inventory and budget.

locals {
  consumers = {
    "inventory-product-published" = { service = "inventory", event = "product-published", types = ["ProductPublished"] }
    "inventory-goods-received"    = { service = "inventory", event = "goods-received", types = ["GoodsReceived"] }
    "budget-goods-received"       = { service = "budget", event = "goods-received", types = ["GoodsReceived"] }
  }

  consuming_services = toset([for consumer in local.consumers : consumer.service])
}

# Queues belong to the service that consumes from them, so they carry that
# service's name and tags.
module "consumer_context" {
  source   = "../../../modules/context"
  for_each = local.consuming_services

  project     = var.project
  environment = var.environment
  component   = each.key
}

module "consumer_queue" {
  source   = "../../../modules/event-consumer-queue"
  for_each = local.consumers

  name = "${module.consumer_context[each.value.service].prefix}-${each.value.event}"
  tags = module.consumer_context[each.value.service].tags

  account_id    = var.aws_account_id
  bus_name      = module.event_bus.bus_name
  source_prefix = var.project
  event_types   = each.value.types

  kms_key_arn = local.facts.messaging_key_arn
}

resource "aws_ssm_parameter" "consumer_queue_url" {
  for_each = local.consumers

  name        = "${module.consumer_context[each.value.service].ssm_path}/queues/${each.value.event}-url"
  description = "Queue the ${each.value.service} service receives ${join(", ", each.value.types)} from."
  type        = "String"
  value       = module.consumer_queue[each.key].queue_url

  tags = module.consumer_context[each.value.service].tags
}
