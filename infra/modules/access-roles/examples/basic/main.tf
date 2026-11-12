module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "access"
}

module "access_roles" {
  source = "../.."

  name = module.context.prefix
  tags = module.context.tags

  account_id          = "333333333333"
  region              = "eu-west-1"
  identity_account_id = "444444444444"
  deploy_subjects     = ["repo:example-org/example-repository:environment:production"]

  resource_prefix          = "meridian-prod-"
  path_prefix              = "/meridian/prod/"
  permissions_boundary_arn = "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary"
  logs_key_alias           = "alias/meridian-prod-logs"

  state_bucket_name = "meridian-shared-tfstate-444444444444-eu-west-1"
  state_key_prefix  = "production"
  state_account_id  = "444444444444"
}
