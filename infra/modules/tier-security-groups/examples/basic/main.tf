module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "network"
}

module "tier_security_groups" {
  source = "../.."

  name           = module.context.prefix
  tags           = module.context.tags
  vpc_id         = "vpc-0123456789abcdef0"
  vpc_cidr_block = "10.30.0.0/16"
}
