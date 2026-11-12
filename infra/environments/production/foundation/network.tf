# The environment's network: three tiers across three zones.

module "network_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "network"
}

module "vpc" {
  source = "../../../modules/vpc"

  name = module.network_context.prefix
  tags = module.network_context.tags

  cidr_block         = var.vpc_cidr
  availability_zones = var.availability_zones
  single_nat_gateway = var.single_nat_gateway

  # The tags a Kubernetes load balancer controller uses to find the subnets
  # for internet-facing and internal load balancers.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

# Private paths to AWS services. The gateway endpoints are attached to the
# private and data route tables, which is what lets the data tier reach S3
# and DynamoDB with no route to the internet.
module "vpc_endpoints" {
  source = "../../../modules/vpc-endpoints"

  name = module.network_context.prefix
  tags = module.network_context.tags

  vpc_id             = module.vpc.vpc_id
  vpc_cidr_block     = module.vpc.cidr_block
  route_table_ids    = concat(module.vpc.private_route_table_ids, [module.vpc.data_route_table_id])
  subnet_ids         = module.vpc.private_subnet_ids
  interface_services = var.interface_endpoint_services
}

module "vpc_flow_logs" {
  source = "../../../modules/vpc-flow-logs"

  name = module.network_context.prefix
  tags = module.network_context.tags

  vpc_id            = module.vpc.vpc_id
  account_id        = var.aws_account_id
  log_group_name    = "/${var.project}/${var.environment}/network/flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_arn       = module.kms_key["logs"].key_arn
}

# One security group per tier. Workload and data store modules attach these
# rather than inventing their own, so the allowed paths are defined once.
module "tier_security_groups" {
  source = "../../../modules/tier-security-groups"

  name = module.network_context.prefix
  tags = module.network_context.tags

  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.cidr_block
}

# Published for other layers and for services. A consumer reads the path
# /<project>/<environment>/network and needs no access to this layer's state.
locals {
  network_parameters = {
    "vpc-id"                          = { type = "String", value = module.vpc.vpc_id }
    "vpc-cidr"                        = { type = "String", value = module.vpc.cidr_block }
    "availability-zones"              = { type = "StringList", value = join(",", module.vpc.availability_zones) }
    "public-subnet-ids"               = { type = "StringList", value = join(",", module.vpc.public_subnet_ids) }
    "private-subnet-ids"              = { type = "StringList", value = join(",", module.vpc.private_subnet_ids) }
    "data-subnet-ids"                 = { type = "StringList", value = join(",", module.vpc.data_subnet_ids) }
    "private-route-table-ids"         = { type = "StringList", value = join(",", module.vpc.private_route_table_ids) }
    "data-route-table-id"             = { type = "String", value = module.vpc.data_route_table_id }
    "flow-log-group"                  = { type = "String", value = module.vpc_flow_logs.log_group_name }
    "s3-prefix-list-id"               = { type = "String", value = module.vpc_endpoints.s3_prefix_list_id }
    "dynamodb-prefix-list-id"         = { type = "String", value = module.vpc_endpoints.dynamodb_prefix_list_id }
    "load-balancer-security-group-id" = { type = "String", value = module.tier_security_groups.load_balancer_security_group_id }
    "application-security-group-id"   = { type = "String", value = module.tier_security_groups.application_security_group_id }
    "data-security-group-id"          = { type = "String", value = module.tier_security_groups.data_security_group_id }
  }
}

resource "aws_ssm_parameter" "network" {
  for_each = local.network_parameters

  name        = "${module.network_context.ssm_path}/${each.key}"
  description = "Network fact published by the foundation layer."
  type        = each.value.type
  value       = each.value.value

  tags = module.network_context.tags
}
