module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "inventory"
}

module "event_stream" {
  source = "../.."

  name       = "${module.context.prefix}-movement-stream"
  tags       = module.context.tags
  account_id = "333333333333"

  data_classification = "internal"
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"

  # Long enough for the inventory service to be down over a weekend and
  # still catch up.
  retention_hours = 72
}

# Attached to the scan intake function's role.
output "produce_policy_json" {
  description = "Policy that lets scan intake write movements."
  value       = module.event_stream.produce_policy_json
}
