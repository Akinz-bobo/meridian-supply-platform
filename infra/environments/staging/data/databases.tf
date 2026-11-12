# Relational databases, one per service that needs one.

# The product master: products, suppliers, units and the result of
# curation. Owned by the catalog service and read by nobody else.
module "catalog_db" {
  source = "../../../modules/postgres-database"

  name = "${module.catalog_context.prefix}-db"

  tags = module.catalog_context.tags

  # Backed up daily to the vault, on top of RDS's own automated backups.
  # A store tag goes on the instance only, not on its log group.
  store_tags = local.backup_tag

  database_name = "catalog"

  data_classification = "confidential"

  subnet_ids         = split(",", local.facts.data_subnet_ids)
  security_group_ids = [local.facts.data_security_group_id]

  kms_key_arn         = local.facts.data_key_arn
  secrets_kms_key_arn = local.facts.secrets_key_arn
  logs_kms_key_arn    = local.facts.logs_key_arn

  instance_class        = var.database_instance_class
  multi_az              = var.database_multi_az
  backup_retention_days = var.database_backup_retention_days
  log_retention_days    = var.log_retention_days

  # A disposable environment can be torn down without ceremony.
  deletion_protection = !var.disposable
  skip_final_snapshot = var.disposable
  apply_immediately   = var.disposable
}

resource "aws_ssm_parameter" "catalog_db" {
  for_each = {
    "db-identifier"        = module.catalog_db.identifier
    "db-address"           = module.catalog_db.address
    "db-port"              = tostring(module.catalog_db.port)
    "db-name"              = module.catalog_db.database_name
    "db-resource-id"       = module.catalog_db.resource_id
    "db-master-secret-arn" = module.catalog_db.master_user_secret_arn
  }

  name        = "${module.catalog_context.ssm_path}/${each.key}"
  description = "Catalog database fact, published by the data layer."
  type        = "String"
  value       = each.value

  tags = module.catalog_context.tags
}
