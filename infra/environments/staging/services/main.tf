# Services layer: the workloads themselves.
#
# Everything below this layer is platform: network, stores, messaging,
# clusters. This layer deploys services onto it. It changes most often, so
# it is the last layer and the smallest plan. See docs/architecture/compute.md.

module "context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "services"
}

locals {
  foundation = "/${var.project}/${var.environment}"

  # Facts published by the layers below, by short name.
  foundation_parameters = {
    vpc_id                          = "network/vpc-id"
    vpc_cidr                        = "network/vpc-cidr"
    private_subnet_ids              = "network/private-subnet-ids"
    load_balancer_security_group_id = "network/load-balancer-security-group-id"
    logs_key_arn                    = "security/kms/logs-key-arn"
    workload_boundary_arn           = "security/iam/workload-boundary-arn"
    ecs_cluster_name                = "compute/ecs-cluster-name"
    ecs_cluster_arn                 = "compute/ecs-cluster-arn"
    https_listener_arn              = "compute/https-listener-arn"
  }
}

data "aws_ssm_parameter" "foundation" {
  for_each = local.foundation_parameters

  name = "${local.foundation}/${each.value}"
}

locals {
  # nonsensitive: these are identifiers, stored as plain String parameters.
  facts = { for name, parameter in data.aws_ssm_parameter.foundation : name => nonsensitive(parameter.value) }

  ra = "${var.aws_region}:${var.aws_account_id}"
}
