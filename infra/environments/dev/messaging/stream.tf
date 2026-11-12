# The movement stream. Warehouse scans do not go over the bus: they arrive
# in bursts and must be applied in order per warehouse, which is what a
# stream partitioned by warehouse gives. See docs/architecture/messaging.md.

module "movement_stream" {
  source = "../../../modules/event-stream"

  # Owned by inventory, which is the service that applies the movements.
  name       = "${module.consumer_context["inventory"].prefix}-movement-stream"
  tags       = module.consumer_context["inventory"].tags
  account_id = var.aws_account_id

  data_classification = "internal"
  kms_key_arn         = local.facts.messaging_key_arn

  # Three days: the inventory service can be down over a weekend and still
  # read every movement when it returns.
  retention_hours = 72
}

resource "aws_ssm_parameter" "movement_stream" {
  for_each = {
    "movement-stream-name" = module.movement_stream.stream_name
    "movement-stream-arn"  = module.movement_stream.stream_arn
  }

  name        = "${module.consumer_context["inventory"].ssm_path}/${each.key}"
  description = "Movement stream fact, published by the messaging layer."
  type        = "String"
  value       = each.value

  tags = module.consumer_context["inventory"].tags
}
