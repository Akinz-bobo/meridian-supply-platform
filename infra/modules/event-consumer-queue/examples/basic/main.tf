# The budget service wants to hear about deliveries.

module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "budget"
}

module "event_consumer_queue" {
  source = "../.."

  name = "${module.context.prefix}-goods-received"
  tags = module.context.tags

  account_id    = "333333333333"
  bus_name      = "meridian-prod-events"
  source_prefix = "meridian"
  event_types   = ["GoodsReceived"]

  kms_key_arn   = "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"
  alarm_actions = ["arn:aws:sns:eu-west-1:333333333333:meridian-prod-alarms"]
}

# Attached to the budget service's role.
output "consume_policy_json" {
  description = "Policy that lets the budget service receive from its queue."
  value       = module.event_consumer_queue.consume_policy_json
}
