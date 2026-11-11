output "state_bucket" {
  description = "Bucket that holds Terraform state. Must match infra/environments/_shared/backend.hcl."
  value       = module.state_bucket.bucket
}

output "state_kms_key_alias" {
  description = "Alias of the key that encrypts state."
  value       = module.state_bucket.kms_key_alias
}
