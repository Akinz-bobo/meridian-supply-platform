module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "logs"
}

module "kms_key" {
  source = "../.."

  name        = module.context.prefix
  tags        = module.context.tags
  description = "Encrypts CloudWatch log groups in production."
  account_id  = "333333333333"

  service_principals = ["logs.eu-west-1.amazonaws.com"]
}
