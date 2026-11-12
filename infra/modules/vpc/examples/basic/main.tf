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
