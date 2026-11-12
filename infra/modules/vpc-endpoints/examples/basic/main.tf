module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "network"
}

module "vpc_endpoints" {
  source = "../.."

  name            = module.context.prefix
  tags            = module.context.tags
  vpc_id          = "vpc-0123456789abcdef0"
  account_id      = "333333333333"
  vpc_cidr_block  = "10.30.0.0/16"
  route_table_ids = ["rtb-0123456789abcdef0"]
  subnet_ids      = ["subnet-0123456789abcdef0"]
}
