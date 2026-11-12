# backup-plan

Central backups for an environment: a vault, a schedule, the rule for what is included, and the role the backup service uses.

What a caller needs to know:

- **A store opts in with a tag**, `Backup = daily` by default. Nothing is listed by name. A new store is backed up from the moment it carries the tag, and a store that should be and is not can be found by the missing tag. Put the tag on the store itself and not on the resources around it: the database and table modules take it as `store_tags`.
- **Recovery points cannot be deleted by hand.** The vault's policy denies deleting a recovery point or shortening its life, to every principal. They leave when their retention ends.
- **The vault is locked** so that retention cannot go below `lock_min_retention_days`. With `null` there is no lock, for a disposable environment.
- **Use a key of the vault's own** for `kms_key_arn`, with `backup.amazonaws.com` named in its key policy. Access to backups is then separate from access to the originals.
- **The service role can only take backups.** Its permissions and its boundary are both AWS's backup policy, so it cannot be given more. Restoring is done by a person with another role, following the [restore runbook](../../../docs/runbooks/restore.md).
- **Backups are kept at least 7 days**, and never less than the vault lock's minimum.
- **This is a second copy.** Each store still has its own protection: point-in-time recovery, automated backups, versioning. The vault is for losing the store and its own backups together.

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "backup"
}

module "backup_plan" {
  source = "../.."

  name       = module.context.prefix
  tags       = module.context.tags
  account_id = "333333333333"

  kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/44444444-4444-4444-4444-444444444444"

  rules = {
    daily   = { schedule = "cron(0 2 * * ? *)", retention_days = 35 }
    monthly = { schedule = "cron(0 3 1 * ? *)", retention_days = 365 }
  }
}

# A store opts in by carrying this tag.
output "selection_tag" {
  description = "Tag that opts a store in to the plan."
  value       = module.backup_plan.selection_tag
}
```

## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.10.0, < 2.0.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| account\_id | Account the vault is in. The backup service may assume the role only on behalf of this account. | `string` | n/a | yes |
| kms\_key\_arn | ARN of the key that encrypts recovery points in the vault. Use a key of the vault's own, so that access to backups is separate from access to the originals. | `string` | n/a | yes |
| name | Name of the vault and the plan, and the prefix of the service role. Build it from the context module's prefix. | `string` | n/a | yes |
| tags | Tags for every resource in the module, and for the recovery points. Take them from the context module. | `map(string)` | n/a | yes |
| force\_destroy | Let Terraform delete the vault while it still holds recovery points. Turn on only in an environment whose data is disposable. | `bool` | `false` | no |
| lock\_min\_retention\_days | Lock the vault so that no recovery point can be given a shorter life than this. With null the vault is not locked, which suits a disposable environment. | `number` | `7` | no |
| rules | Backup rules, keyed by name. schedule is a cron expression in UTC, in the form AWS uses: cron(minute hour day-of-month month day-of-week year). | <pre>map(object({<br/>    schedule       = string<br/>    retention_days = number<br/>  }))</pre> | <pre>{<br/>  "daily": {<br/>    "retention_days": 35,<br/>    "schedule": "cron(0 2 * * ? *)"<br/>  }<br/>}</pre> | no |
| selection\_tag | Tag that opts a resource in to this plan. A resource with this key and value is backed up, and nothing else is. | <pre>object({<br/>    key   = string<br/>    value = string<br/>  })</pre> | <pre>{<br/>  "key": "Backup",<br/>  "value": "daily"<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| plan\_id | Identifier of the backup plan. |
| role\_arn | ARN of the role the backup service uses. |
| selection\_tag | Tag that opts a resource in to this plan. Put it on a store to have it backed up. |
| vault\_arn | ARN of the backup vault. |
| vault\_name | Name of the backup vault. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_backup_plan.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan) | resource |
| [aws_backup_selection.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_selection) | resource |
| [aws_backup_vault.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_backup_vault_lock_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_lock_configuration) | resource |
| [aws_backup_vault_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_policy) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
<!-- END_TF_DOCS -->
