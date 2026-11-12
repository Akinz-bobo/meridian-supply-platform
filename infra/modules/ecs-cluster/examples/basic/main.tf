module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "compute"
}

module "ecs_cluster" {
  source = "../.."

  name = module.context.prefix
  tags = module.context.tags

  exec_log_group_name = "${module.context.ssm_path}/ecs-exec"
  logs_kms_key_arn    = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
}
