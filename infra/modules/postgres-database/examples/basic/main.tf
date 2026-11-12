module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "catalog"
}

module "postgres_database" {
  source = "../.."

  name          = "${module.context.prefix}-db"
  tags          = module.context.tags
  database_name = "catalog"

  data_classification = "confidential"

  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1", "subnet-0123456789abcdef2"]
  security_group_ids = ["sg-0123456789abcdef0"]

  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
  secrets_kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/22222222-2222-2222-2222-222222222222"
  logs_kms_key_arn    = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
}
