module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "catalog"
}

module "container_repository" {
  source = "../.."

  name       = module.context.prefix
  tags       = module.context.tags
  account_id = "333333333333"

  kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
}

# Attached to the execution role of the catalog service's tasks.
output "pull_policy_json" {
  description = "Policy that lets the catalog service's tasks pull its image."
  value       = module.container_repository.pull_policy_json
}
