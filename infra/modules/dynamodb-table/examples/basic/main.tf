module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "inventory"
}

# An append-only ledger: one item per stock movement, grouped by batch, with
# an index that lists a warehouse's movements for a day.
module "dynamodb_table" {
  source = "../.."

  name       = "${module.context.prefix}-movements"
  tags       = module.context.tags
  account_id = "333333333333"

  data_classification = "internal"
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"

  hash_key  = "pk"
  range_key = "sk"
  attributes = {
    pk     = "S"
    sk     = "S"
    gsi1pk = "S"
    gsi1sk = "S"
  }

  global_secondary_indexes = [
    { name = "by-warehouse-day", hash_key = "gsi1pk", range_key = "gsi1sk" },
  ]

  # Every new movement is streamed to the analytics pipeline.
  stream_view_type = "NEW_IMAGE"
}

# Attached to the inventory service's role.
output "write_policy_json" {
  description = "Policy for the inventory service's role."
  value       = module.dynamodb_table.write_policy_json
}
