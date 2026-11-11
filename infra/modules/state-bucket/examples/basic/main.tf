module "context" {
  source = "../../../context"

  environment = "shared"
  component   = "tfstate"
}

module "state_bucket" {
  source = "../.."

  # Bucket names are global, so include the account and region.
  name = "${module.context.prefix}-444444444444-eu-west-1"
  tags = module.context.tags
}

output "bucket" {
  description = "Use this as the bucket in the S3 backend configuration."
  value       = module.state_bucket.bucket
}
