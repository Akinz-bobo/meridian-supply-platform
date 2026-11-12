# The sample service on ECS. See services/sample.

module "sample_context" {
  source = "../../../modules/context"

  project     = var.project
  environment = var.environment
  component   = "sample"
}

# The image the pipeline pushed last. See compute/registry.tf.
data "aws_ssm_parameter" "sample_image" {
  name = "${module.sample_context.ssm_path}/image"
}

locals {
  sample_image     = nonsensitive(data.aws_ssm_parameter.sample_image.value)
  sample_log_group = "${module.sample_context.ssm_path}/ecs"
}

# What ECS needs in order to start the task. Nothing the application uses.
data "aws_iam_policy_document" "sample_start" {
  statement {
    sid = "PullTheImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:${local.ra}:repository/${module.sample_context.prefix}"]
  }

  statement {
    sid       = "LogInToTheRegistry"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${local.ra}:log-group:${local.sample_log_group}:*"]
  }
}

module "sample_execution_role" {
  source = "../../../modules/workload-role"

  name        = "${module.sample_context.prefix}-execution-role"
  tags        = module.sample_context.tags
  description = "Lets ECS start tasks of the sample service: pull its image and write its logs."
  workload    = "ecs-task"
  account_id  = var.aws_account_id

  permissions_boundary_arn = local.facts.workload_boundary_arn

  policies = {
    start-the-task = data.aws_iam_policy_document.sample_start.json
  }
}

# What the application runs as. The sample service calls no AWS API, so its
# role has no permissions. It exists so that the service has an identity of
# its own, which is what its /identity endpoint reports.
module "sample_task_role" {
  source = "../../../modules/workload-role"

  name        = "${module.sample_context.prefix}-task-role"
  tags        = module.sample_context.tags
  description = "Identity of the sample service on ECS. It has no permissions."
  workload    = "ecs-task"
  account_id  = var.aws_account_id

  permissions_boundary_arn = local.facts.workload_boundary_arn
}

module "sample_service" {
  source = "../../../modules/ecs-service"

  name = module.sample_context.prefix
  tags = module.sample_context.tags

  cluster_arn  = local.facts.ecs_cluster_arn
  cluster_name = local.facts.ecs_cluster_name

  vpc_id         = local.facts.vpc_id
  vpc_cidr_block = local.facts.vpc_cidr
  subnet_ids     = split(",", local.facts.private_subnet_ids)

  image = local.sample_image

  execution_role_arn = module.sample_execution_role.role_arn
  task_role_arn      = module.sample_task_role.role_arn

  listener_arn                    = local.facts.https_listener_arn
  listener_rule_priority          = 100
  path_patterns                   = ["/sample", "/sample/*"]
  health_check_path               = "/sample/healthz"
  load_balancer_security_group_id = local.facts.load_balancer_security_group_id

  environment = {
    SERVICE_NAME = "sample"
    ENVIRONMENT  = var.environment
    PLATFORM     = "ecs"
    VERSION      = element(split(":", local.sample_image), length(split(":", local.sample_image)) - 1)
  }

  desired_count = var.service_desired_count

  log_group_name     = local.sample_log_group
  logs_kms_key_arn   = local.facts.logs_key_arn
  log_retention_days = var.log_retention_days
}
