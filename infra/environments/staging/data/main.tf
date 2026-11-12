# Data layer: the stores that hold the platform's data.
#
# It is a layer of its own because stores change for different reasons than
# the network does, and because a mistake here is the hardest to undo. A
# change to a security group should never produce a plan that also touches
# a database.
#
# Everything this layer needs from the foundation layer is read from
# Parameter Store. It never reads the foundation layer's state.

module "context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "data"
}

locals {
  foundation = "/${var.project}/${var.environment}"

  # Facts published by the foundation layer, by short name.
  foundation_parameters = {
    vpc_id                 = "network/vpc-id"
    data_subnet_ids        = "network/data-subnet-ids"
    private_subnet_ids     = "network/private-subnet-ids"
    data_security_group_id = "network/data-security-group-id"
    data_key_arn           = "security/kms/data-key-arn"
    logs_key_arn           = "security/kms/logs-key-arn"
    secrets_key_arn        = "security/kms/secrets-key-arn"
    workload_boundary_arn  = "security/iam/workload-boundary-arn"
  }
}

data "aws_ssm_parameter" "foundation" {
  for_each = local.foundation_parameters

  name = "${local.foundation}/${each.value}"
}

locals {
  # nonsensitive: these are identifiers, stored as plain String parameters.
  # The provider marks every parameter value sensitive because it cannot
  # know that, which would hide them from plans and make every resource
  # that uses one unreadable in review.
  facts = { for name, parameter in data.aws_ssm_parameter.foundation : name => nonsensitive(parameter.value) }
}
