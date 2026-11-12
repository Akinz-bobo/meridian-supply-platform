# Compute layer: where workloads run.
#
# The registry, the load balancer, the ECS and EKS clusters and the ERP
# gateway host. It is applied after the messaging layer and reads what it
# needs from Parameter Store. See docs/architecture/compute.md.

module "context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "compute"
}

locals {
  foundation = "/${var.project}/${var.environment}"

  # Facts published by the layers below, by short name.
  foundation_parameters = {
    vpc_id                          = "network/vpc-id"
    vpc_cidr                        = "network/vpc-cidr"
    public_subnet_ids               = "network/public-subnet-ids"
    private_subnet_ids              = "network/private-subnet-ids"
    load_balancer_security_group_id = "network/load-balancer-security-group-id"
    application_security_group_id   = "network/application-security-group-id"
    data_key_arn                    = "security/kms/data-key-arn"
    logs_key_arn                    = "security/kms/logs-key-arn"
    secrets_key_arn                 = "security/kms/secrets-key-arn"
    workload_boundary_arn           = "security/iam/workload-boundary-arn"
  }
}

data "aws_ssm_parameter" "foundation" {
  for_each = local.foundation_parameters

  name = "${local.foundation}/${each.value}"
}

locals {
  # nonsensitive: these are identifiers, stored as plain String parameters.
  facts = { for name, parameter in data.aws_ssm_parameter.foundation : name => nonsensitive(parameter.value) }
}
