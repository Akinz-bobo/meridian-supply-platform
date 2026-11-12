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

# Which image of the service is deployed. Terraform creates the parameter
# and the pipeline sets its value each time it pushes an image
# (scripts/push-image.sh). The services layer reads it. Keeping the value
# out of Terraform's hands means a deployment is "push, then apply", and
# this parameter is the record of what is running.
resource "aws_ssm_parameter" "sample_image" {
  name        = "${module.sample_context.ssm_path}/image"
  description = "Image of the sample service that is deployed. Set by the pipeline after a push."
  type        = "String"
  value       = "unset"

  tags = module.sample_context.tags

  lifecycle {
    ignore_changes = [value]
  }
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
