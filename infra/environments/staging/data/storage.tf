# Object storage.

module "catalog_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "catalog"
}

# Where suppliers' product files arrive, kept exactly as received. The
# curation workflow reads them from here. Files are kept for a year so a
# dispute about what a supplier sent can be settled from the original.
module "supplier_uploads" {
  source = "../../../modules/data-bucket"

  # Bucket names are global, so the account and region are part of the name.
  name = "${module.catalog_context.prefix}-uploads-${var.aws_account_id}-${var.aws_region}"
  tags = module.catalog_context.tags

  data_classification = "confidential"
  kms_key_arn         = local.facts.data_key_arn

  expiration_days = 365
  transitions     = [{ days = 90, storage_class = "STANDARD_IA" }]

  # The curation workflow starts from the event for a new object.
  eventbridge_notifications = true

  force_destroy = var.disposable
}

resource "aws_ssm_parameter" "supplier_uploads" {
  for_each = {
    "uploads-bucket-name" = module.supplier_uploads.bucket_name
    "uploads-bucket-arn"  = module.supplier_uploads.bucket_arn
  }

  name        = "${module.catalog_context.ssm_path}/${each.key}"
  description = "Supplier uploads bucket, published by the data layer."
  type        = "String"
  value       = each.value

  tags = module.catalog_context.tags
}
