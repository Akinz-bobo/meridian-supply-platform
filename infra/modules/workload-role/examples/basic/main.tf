module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "catalog"
}

data "aws_iam_policy_document" "read_own_parameters" {
  statement {
    sid       = "ReadOwnConfiguration"
    actions   = ["ssm:GetParameter", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:eu-west-1:333333333333:parameter${module.context.ssm_path}/*"]
  }
}

module "workload_role" {
  source = "../.."

  name        = "${module.context.prefix}-task-role"
  tags        = module.context.tags
  description = "Runs the catalog service on ECS."
  workload    = "ecs-task"
  account_id  = "333333333333"

  permissions_boundary_arn = "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary"

  policies = {
    read-own-parameters = data.aws_iam_policy_document.read_own_parameters.json
  }
}
