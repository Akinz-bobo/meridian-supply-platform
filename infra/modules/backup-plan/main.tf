# Central backups: a vault, a schedule, and a rule for what is included.
#
# Each store already protects itself: point-in-time recovery, automated
# backups, versioning. This adds a second copy that is managed in one
# place, kept on one schedule, and held in a vault that the roles able to
# damage the original cannot delete from.
#
# A store opts in with a tag. Nothing is listed here by name, so a new
# store is backed up the moment it carries the tag, and a store that should
# be backed up and is not can be found by looking for the missing tag.

locals {
  arn = "arn:aws"

  # AWS's own policy for the backup service. It is the role's permissions
  # and also its boundary, so the role can never be given more.
  service_policy_arn = "${local.arn}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_vault" "this" {
  name        = var.name
  kms_key_arn = var.kms_key_arn

  # Refuse to delete a vault that still holds recovery points, unless the
  # environment is disposable.
  force_destroy = var.force_destroy

  tags = var.tags
}

# Nobody deletes a recovery point by hand or shortens its life, whatever
# their IAM permissions say. Recovery points leave the vault when their
# retention ends, and in no other way.
data "aws_iam_policy_document" "vault" {
  statement {
    sid    = "RecoveryPointsAreNotDeletedByHand"
    effect = "Deny"
    actions = [
      "backup:DeleteRecoveryPoint",
      "backup:UpdateRecoveryPointLifecycle",
    ]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_backup_vault_policy" "this" {
  backup_vault_name = aws_backup_vault.this.name
  policy            = data.aws_iam_policy_document.vault.json
}

# A lock in governance mode: retention cannot be set below the minimum,
# and the lock can be removed only by a principal with a specific
# permission that no pipeline or workload role has.
resource "aws_backup_vault_lock_configuration" "this" {
  count = var.lock_min_retention_days == null ? 0 : 1

  backup_vault_name  = aws_backup_vault.this.name
  min_retention_days = var.lock_min_retention_days
}

data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "BackupServiceForThisAccount"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.name}-role"
  description          = "Lets AWS Backup take backups of the stores that carry the backup tag."
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = local.service_policy_arn

  tags = var.tags
}

# Backups only. Restoring is done by a person, with a role of their own,
# following the restore runbook. The service's access to the vault's key
# comes from the key policy, which the caller sets when creating the key.
resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = local.service_policy_arn
}

resource "aws_backup_plan" "this" {
  name = var.name

  dynamic "rule" {
    for_each = var.rules

    content {
      rule_name         = rule.key
      target_vault_name = aws_backup_vault.this.name
      schedule          = rule.value.schedule

      # A backup that has not started within an hour is abandoned and
      # reported, not left to start at a busy time.
      start_window      = 60
      completion_window = 480

      lifecycle {
        delete_after = rule.value.retention_days
      }

      # The recovery point keeps the tags of what it is a copy of, so its
      # classification travels with it.
      recovery_point_tags = var.tags
    }
  }

  tags = var.tags
}

resource "aws_backup_selection" "this" {
  name         = var.name
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.this.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.selection_tag.key
    value = var.selection_tag.value
  }
}
