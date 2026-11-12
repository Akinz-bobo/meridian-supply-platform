module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "network"
}

module "vpc_flow_logs" {
  source = "../.."

  name           = module.context.prefix
  tags           = module.context.tags
  vpc_id         = "vpc-0123456789abcdef0"
  account_id     = "333333333333"
  log_group_name = "/meridian/prod/network/flow-logs"
  kms_key_arn    = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"

  permissions_boundary_arn = "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary"
}
