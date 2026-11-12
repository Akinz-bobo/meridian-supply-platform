module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "workload-boundary"
}

module "permission_boundary" {
  source = "../.."

  name            = module.context.prefix
  tags            = module.context.tags
  resource_prefix = "meridian-prod-"
  path_prefix     = "/meridian/prod/"
  account_id      = "333333333333"
  region          = "eu-west-1"
}
