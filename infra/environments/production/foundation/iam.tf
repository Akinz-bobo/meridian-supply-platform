# Identity and access foundations. See docs/architecture/access-model.md.

locals {
  resource_prefix = "${var.project}-${var.environment}-"
  path_prefix     = "/${var.project}/${var.environment}/"
}

module "boundary_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "workload-boundary"
}

# The ceiling for every workload role in the environment.
module "permission_boundary" {
  source = "../../../modules/permission-boundary"

  name = module.boundary_context.prefix
  tags = module.security_context.tags

  resource_prefix = local.resource_prefix
  path_prefix     = local.path_prefix
  account_id      = var.aws_account_id
  region          = var.aws_region
}

module "access_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "access"
}

# How the pipeline and people get in.
module "access_roles" {
  source = "../../../modules/access-roles"

  name = module.access_context.prefix
  tags = module.security_context.tags

  account_id          = var.aws_account_id
  region              = var.aws_region
  identity_account_id = var.identity_account_id
  deploy_subjects     = ["repo:${var.github_repository}:environment:${var.github_environment}"]

  resource_prefix          = local.resource_prefix
  path_prefix              = local.path_prefix
  permissions_boundary_arn = module.permission_boundary.policy_arn
  logs_key_alias           = module.kms_key["logs"].alias_name

  state_bucket_name = var.state_bucket_name
  state_key_prefix  = var.state_key_prefix
  state_account_id  = var.state_account_id

  allow_key_deletion = var.disposable
}

module "account_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "account"
}

# Account-wide defaults that hold even for resources created by hand.
module "account_baseline" {
  source = "../../../modules/account-baseline"

  name = module.account_context.prefix
  tags = module.security_context.tags

  ebs_kms_key_arn = module.kms_key["data"].key_arn
}

resource "aws_ssm_parameter" "iam" {
  for_each = {
    "workload-boundary-arn" = module.permission_boundary.policy_arn
    "deploy-role-arn"       = module.access_roles.deploy_role_arn
    "operator-role-arn"     = module.access_roles.operator_role_arn
    "audit-role-arn"        = module.access_roles.audit_role_arn
  }

  name        = "${module.security_context.ssm_path}/iam/${each.key}"
  description = "Identity fact published by the foundation layer."
  type        = "String"
  value       = each.value

  tags = module.security_context.tags
}
