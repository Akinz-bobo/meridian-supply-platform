module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "events"
}

module "event_bus" {
  source = "../.."

  name = module.context.prefix
  tags = module.context.tags

  account_id    = "333333333333"
  source_prefix = "meridian"
  publishers    = ["catalog", "inventory", "procurement"]

  kms_key_arn      = "arn:aws:kms:eu-west-1:333333333333:key/55555555-5555-5555-5555-555555555555"
  logs_kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
}

# Attached to the catalog service's role. It can publish as meridian.catalog
# and as nothing else.
output "catalog_publish_policy_json" {
  description = "Policy that lets the catalog service publish its events."
  value       = module.event_bus.publish_policy_json["catalog"]
}
