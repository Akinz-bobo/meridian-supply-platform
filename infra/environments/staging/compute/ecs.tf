# The ECS cluster that Fargate services run in.

module "ecs_cluster" {
  source = "../../../modules/ecs-cluster"

  name = module.context.prefix
  tags = module.context.tags

  exec_log_group_name = "${module.context.ssm_path}/ecs-exec"
  logs_kms_key_arn    = local.facts.logs_key_arn
}

resource "aws_ssm_parameter" "ecs_cluster" {
  for_each = {
    "ecs-cluster-name" = module.ecs_cluster.cluster_name
    "ecs-cluster-arn"  = module.ecs_cluster.cluster_arn
  }

  name        = "${module.context.ssm_path}/${each.key}"
  description = "ECS cluster fact, published by the compute layer."
  type        = "String"
  value       = each.value

  tags = module.context.tags
}
