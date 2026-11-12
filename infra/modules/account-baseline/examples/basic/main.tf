module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "account"
}

module "account_baseline" {
  source = "../.."

  name            = module.context.prefix
  tags            = module.context.tags
  ebs_kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
}
