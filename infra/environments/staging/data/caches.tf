# Caches.

# Stock availability by product and warehouse, read far more often than it
# changes. It is filled from the stock level table and can be rebuilt from
# it at any time, so losing it costs speed and not data.
module "stock_cache" {
  source = "../../../modules/redis-cache"

  name        = "${module.inventory_context.prefix}-cache"
  tags        = module.inventory_context.tags
  description = "Read cache of stock availability for the inventory service."
  account_id  = var.aws_account_id

  data_classification = "internal"

  subnet_ids         = split(",", local.facts.data_subnet_ids)
  security_group_ids = [local.facts.data_security_group_id]

  kms_key_arn        = local.facts.data_key_arn
  logs_kms_key_arn   = local.facts.logs_key_arn
  log_group_name     = "${module.inventory_context.ssm_path}/cache/slow-log"
  log_retention_days = var.log_retention_days

  node_type = var.cache_node_type
  replicas  = var.cache_replicas

  # The inventory service may read and write keys under stock: and nothing
  # else, and may run no administrative or dangerous command.
  users = {
    inventory = {
      access_string = "on ~stock:* +@read +@write +@connection -@dangerous"
    }
  }

  # A disposable environment keeps no snapshots and changes at once.
  snapshot_retention_days = var.disposable ? 0 : 1
  apply_immediately       = var.disposable
}

resource "aws_ssm_parameter" "stock_cache" {
  for_each = {
    "cache-primary-address" = module.stock_cache.primary_endpoint_address
    "cache-reader-address"  = module.stock_cache.reader_endpoint_address
    "cache-port"            = tostring(module.stock_cache.port)
    "cache-user"            = module.stock_cache.user_ids["inventory"]
  }

  name        = "${module.inventory_context.ssm_path}/${each.key}"
  description = "Stock cache fact, published by the data layer."
  type        = "String"
  value       = each.value

  tags = module.inventory_context.tags
}
