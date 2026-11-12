module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "network"
}

module "vpc" {
  source = "../.."

  name               = module.context.prefix
  tags               = module.context.tags
  cidr_block         = "10.30.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

# A VPC is always paired with flow logs. They are a separate module so the
# destination and retention can change without touching the network.
module "vpc_flow_logs" {
  source = "../../../vpc-flow-logs"

  name           = module.context.prefix
  tags           = module.context.tags
  vpc_id         = module.vpc.vpc_id
  account_id     = "333333333333"
  log_group_name = "/meridian/prod/network/flow-logs"
}
