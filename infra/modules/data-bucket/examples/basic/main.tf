module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "catalog"
}

module "data_bucket" {
  source = "../.."

  name = "${module.context.prefix}-uploads-333333333333-eu-west-1"
  tags = module.context.tags

  data_classification = "confidential"
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"

  # Supplier files are kept for a year, in cheaper storage after 90 days.
  expiration_days = 365
  transitions     = [{ days = 90, storage_class = "STANDARD_IA" }]

  # Tell the event bus when a supplier uploads a file.
  eventbridge_notifications = true
}

# Attached to the role of the service that reads and writes the bucket.
output "write_policy_json" {
  description = "Policy for the curation workflow's role."
  value       = module.data_bucket.write_policy_json
}
