# A customer managed encryption key with an alias and a key policy.
#
# The key policy does two things. It lets the account decide access through
# IAM policies, so that who can use the key is managed in one place. And it
# lets named AWS services use the key on the account's behalf, each limited
# to requests that come from this account.
#
# Rotation is always on and the key cannot be deleted in less than two weeks.

data "aws_iam_policy_document" "key" {
  # Without this statement, IAM policies in the account have no effect on
  # the key and it can only be managed through the key policy itself.
  statement {
    sid       = "AccountManagesAccessThroughIam"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = length(var.service_principals) > 0 ? [1] : []

    content {
      sid = "ServicesUseTheKeyForThisAccount"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = sort(tolist(var.service_principals))
      }

      # A service acts for many accounts. This limits it to requests made
      # on behalf of this one.
      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [var.account_id]
      }
    }
  }
}

resource "aws_kms_key" "this" {
  description             = var.description
  enable_key_rotation     = true
  rotation_period_in_days = var.rotation_period_in_days
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.key.json

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}
