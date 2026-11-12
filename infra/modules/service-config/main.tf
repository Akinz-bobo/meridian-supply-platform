# A service's configuration and secrets, under one path that belongs to it.
#
#   <path>/config/<key>     plain configuration, in Parameter Store
#   <path>/secrets/<name>   secrets, in Secrets Manager
#
# Because everything a service owns is under its path, "this service may
# read its own configuration and nobody else's" is one IAM statement. The
# module renders that statement as an output, ready to attach to the
# service's role.
#
# Secret values never pass through Terraform state. A generated secret is
# produced by an ephemeral resource and written through a write-only
# argument, and neither is stored. A secret that is not generated is created
# empty and its value is put there by whoever owns it.

data "aws_region" "current" {}

locals {
  arn = "arn:aws"
  ra  = "${data.aws_region.current.region}:${var.account_id}"

  generated = { for name, secret in var.secrets : name => secret.generate if secret.generate != null }
  rotated   = { for name, secret in var.secrets : name => secret.rotation if secret.rotation != null }
}

resource "aws_ssm_parameter" "config" {
  for_each = var.parameters

  name        = "${var.path}/config/${each.key}"
  description = "Configuration of the service that owns ${var.path}."
  type        = "String"
  value       = each.value

  tags = var.tags
}

resource "aws_secretsmanager_secret" "this" {
  for_each = var.secrets

  name                    = "${var.path}/secrets/${each.key}"
  description             = each.value.description
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.recovery_window_in_days

  tags = var.tags
}

# Exists only while Terraform runs. It is never written to state or to a
# plan file.
ephemeral "aws_secretsmanager_random_password" "generated" {
  for_each = local.generated

  password_length     = each.value.length
  exclude_punctuation = each.value.exclude_punctuation
}

resource "aws_secretsmanager_secret_version" "generated" {
  for_each = local.generated

  secret_id = aws_secretsmanager_secret.this[each.key].id

  # Write-only: sent to AWS and not kept. The version number is what
  # Terraform tracks. Raising it generates and stores a new value.
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.generated[each.key].random_password
  secret_string_wo_version = each.value.version
}

resource "aws_secretsmanager_secret_rotation" "this" {
  for_each = local.rotated

  secret_id           = aws_secretsmanager_secret.this[each.key].id
  rotation_lambda_arn = each.value.lambda_arn

  rotation_rules {
    automatically_after_days = each.value.automatically_after_days
  }
}

# The whole of a service's read access to its own configuration.
data "aws_iam_policy_document" "read" {
  statement {
    sid       = "ReadOwnParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["${local.arn}:ssm:${local.ra}:parameter${var.path}/*"]
  }

  dynamic "statement" {
    for_each = length(var.secrets) > 0 ? [1] : []

    content {
      sid       = "ReadOwnSecrets"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = ["${local.arn}:secretsmanager:${local.ra}:secret:${var.path}/secrets/*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.secrets) > 0 ? [1] : []

    content {
      sid       = "DecryptOwnSecrets"
      actions   = ["kms:Decrypt"]
      resources = ["${local.arn}:kms:${local.ra}:key/*"]

      condition {
        test     = "ForAnyValue:StringEquals"
        variable = "kms:ResourceAliases"
        values   = [var.kms_key_alias]
      }

      # The key may be used only by way of Secrets Manager, and only for a
      # secret under this service's path.
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${data.aws_region.current.region}.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:SecretARN"
        values   = ["${local.arn}:secretsmanager:${local.ra}:secret:${var.path}/secrets/*"]
      }
    }
  }
}
