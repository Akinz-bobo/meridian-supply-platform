# Encryption keys. One key per class of data, not one per resource and not
# one for everything. See docs/architecture/encryption.md.

locals {
  keys = {
    data = {
      description = "Encrypts data at rest in the ${var.environment} environment: databases, tables, caches and buckets."
      services    = []
    }
    logs = {
      description = "Encrypts CloudWatch log groups in the ${var.environment} environment."
      services    = ["logs.${var.aws_region}.amazonaws.com"]
    }
    messaging = {
      description = "Encrypts queues, topics and streams in the ${var.environment} environment."
      # Services that deliver into an encrypted queue or topic need to
      # generate data keys: SNS to SQS, EventBridge to SQS, S3 notifications.
      services = ["events.amazonaws.com", "s3.amazonaws.com", "sns.amazonaws.com"]
    }
    secrets = {
      description = "Encrypts secrets and secure parameters in the ${var.environment} environment."
      services    = []
    }
  }
}

module "security_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "security"
}

module "key_context" {
  source   = "../../../modules/context"
  for_each = local.keys

  project     = var.project
  environment = var.environment
  component   = each.key
}

module "kms_key" {
  source   = "../../../modules/kms-key"
  for_each = local.keys

  name = module.key_context[each.key].prefix
  tags = module.security_context.tags

  description        = each.value.description
  account_id         = var.aws_account_id
  service_principals = each.value.services
}

resource "aws_ssm_parameter" "kms_key_arn" {
  for_each = local.keys

  name        = "${module.security_context.ssm_path}/kms/${each.key}-key-arn"
  description = "ARN of the ${each.key} encryption key."
  type        = "String"
  value       = module.kms_key[each.key].key_arn

  tags = module.security_context.tags
}
