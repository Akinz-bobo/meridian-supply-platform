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
