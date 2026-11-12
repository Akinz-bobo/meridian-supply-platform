module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "catalog"
}

module "service_config" {
  source = "../.."

  path       = module.context.ssm_path
  tags       = module.context.tags
  account_id = "333333333333"

  kms_key_arn   = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
  kms_key_alias = "alias/meridian-prod-secrets"

  parameters = {
    log-level          = "info"
    supplier-file-size = "50"
  }

  secrets = {
    # Created with a random value that never enters Terraform state.
    webhook-signing-key = {
      description = "Signs webhooks sent to suppliers."
      generate    = {}
    }
    # Created empty. The value is issued by the partner and stored by hand.
    partner-api-token = {
      description = "Token for the partner's price feed."
    }
  }
}

# The policy is attached to the service's own role.
output "read_policy_json" {
  description = "Policy for the catalog service's role."
  value       = module.service_config.read_policy_json
}
