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
}
