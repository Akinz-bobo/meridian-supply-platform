# Central backups. See docs/runbooks/restore.md.

module "backup_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "backup"
}

# The vault has a key of its own. Access to backups is then separate from
# access to the originals: a role that can decrypt the catalog database
# cannot, by that, read a backup of it.
module "backup_key" {
  source = "../../../modules/kms-key"

  name = module.backup_context.prefix
  tags = module.backup_context.tags

  description        = "Encrypts recovery points in the backup vault of the ${var.environment} environment."
  account_id         = var.aws_account_id
  service_principals = ["backup.amazonaws.com"]
}

module "backup" {
  source = "../../../modules/backup-plan"

  name       = module.backup_context.prefix
  tags       = module.backup_context.tags
  account_id = var.aws_account_id

  kms_key_arn = module.backup_key.key_arn

  rules = {
    daily = {
      schedule       = "cron(0 2 * * ? *)"
      retention_days = 35
    }
  }

  # A disposable environment has no vault lock and can be emptied.
  lock_min_retention_days = var.disposable ? null : 7
  force_destroy           = var.disposable
}

locals {
  # Put on a store to have it backed up by the plan above.
  backup_tag = { (module.backup.selection_tag.key) = module.backup.selection_tag.value }
}

resource "aws_ssm_parameter" "backup" {
  for_each = {
    "vault-name" = module.backup.vault_name
    "vault-arn"  = module.backup.vault_arn
    "plan-id"    = module.backup.plan_id
  }

  name        = "${module.backup_context.ssm_path}/${each.key}"
  description = "Backup fact, published by the data layer."
  type        = "String"
  value       = each.value

  tags = module.backup_context.tags
}
