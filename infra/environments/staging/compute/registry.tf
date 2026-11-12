# Container image repositories, one per service.

module "sample_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "sample"
}

# The sample service: the container that proves each compute platform. It
# is deployed to ECS and to EKS. See services/sample.
module "sample_repository" {
  source = "../../../modules/container-repository"

  name       = module.sample_context.prefix
  tags       = module.sample_context.tags
  account_id = var.aws_account_id

  kms_key_arn = local.facts.data_key_arn

  force_delete = var.disposable
}

resource "aws_ssm_parameter" "sample_repository" {
  for_each = {
    "repository-name" = module.sample_repository.repository_name
    "repository-url"  = module.sample_repository.repository_url
  }

  name        = "${module.sample_context.ssm_path}/${each.key}"
  description = "Sample service image repository, published by the compute layer."
  type        = "String"
  value       = each.value

  tags = module.sample_context.tags
}
