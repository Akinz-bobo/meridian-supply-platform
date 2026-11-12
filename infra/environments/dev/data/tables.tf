# DynamoDB tables. The key design of both is in
# docs/architecture/inventory-data-model.md.

module "inventory_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "inventory"
}

# The ledger of stock movements: append-only, and the source of truth for
# stock (rule INV-6). Stock levels can be rebuilt from it.
module "movements" {
  source = "../../../modules/dynamodb-table"

  name = "${module.inventory_context.prefix}-movements"

  # The ledger is the audit record of stock and cannot be rebuilt from
  # anything else, so it is also backed up daily to the vault.
  tags       = module.inventory_context.tags
  store_tags = local.backup_tag

  account_id = var.aws_account_id

  data_classification = "internal"
  kms_key_arn         = local.facts.data_key_arn

  hash_key  = "pk"
  range_key = "sk"
  attributes = {
    pk     = "S"
    sk     = "S"
    gsi1pk = "S"
    gsi1sk = "S"
  }

  global_secondary_indexes = [
    # A warehouse's movements for one day, in time order.
    { name = "by-warehouse-day", hash_key = "gsi1pk", range_key = "gsi1sk" },
  ]

  # Every new movement is streamed, to update stock levels downstream and
  # to feed the data lake.
  stream_view_type = "NEW_IMAGE"

  deletion_protection = !var.disposable
}

# Current stock per product, warehouse, expiry date and batch. Written only
# with conditional updates, which is what keeps stock from going negative
# (rule INV-5).
module "stock_levels" {
  source = "../../../modules/dynamodb-table"

  name       = "${module.inventory_context.prefix}-stock-levels"
  tags       = module.inventory_context.tags
  account_id = var.aws_account_id

  data_classification = "internal"
  kms_key_arn         = local.facts.data_key_arn

  hash_key  = "pk"
  range_key = "sk"
  attributes = {
    pk     = "S"
    sk     = "S"
    gsi1pk = "S"
    gsi1sk = "S"
    gsi2pk = "S"
    gsi2sk = "S"
  }

  global_secondary_indexes = [
    # Every batch that expires on a given day, for the quarantine sweep
    # (rule INV-4). Only keys are projected: the sweep needs to know which
    # items to update and nothing else.
    { name = "by-expiry-date", hash_key = "gsi1pk", range_key = "gsi1sk", projection_type = "KEYS_ONLY" },
    # Everywhere a batch is held, for a recall (rule INV-7).
    { name = "by-batch", hash_key = "gsi2pk", range_key = "gsi2sk" },
  ]

  deletion_protection = !var.disposable
}

resource "aws_ssm_parameter" "inventory_tables" {
  for_each = {
    "movements-table-name"    = module.movements.table_name
    "movements-table-arn"     = module.movements.table_arn
    "movements-stream-arn"    = module.movements.stream_arn
    "stock-levels-table-name" = module.stock_levels.table_name
    "stock-levels-table-arn"  = module.stock_levels.table_arn
  }

  name        = "${module.inventory_context.ssm_path}/${each.key}"
  description = "Inventory table fact, published by the data layer."
  type        = "String"
  value       = each.value

  tags = module.inventory_context.tags
}
