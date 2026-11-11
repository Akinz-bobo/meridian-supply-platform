# Foundation layer: what every other layer of the environment builds on.
#
# It starts with the environment's identity. The network and the security
# baseline are added to this layer in milestone 2.

module "context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "platform"
}

data "aws_caller_identity" "current" {}

# Other layers and services discover facts about the environment from
# Parameter Store, not from this layer's state. That keeps layers loosely
# coupled: a consumer needs read access to a parameter path, not to a state
# file that may contain secrets.
resource "aws_ssm_parameter" "environment" {
  name        = "${module.context.ssm_path}/environment"
  description = "Identity of this environment, for services and other layers to read."
  type        = "String"

  value = jsonencode({
    project     = var.project
    environment = var.environment
    region      = var.aws_region
    account_id  = data.aws_caller_identity.current.account_id
  })

  tags = module.context.tags
}
