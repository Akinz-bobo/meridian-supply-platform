module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "catalog"
}

module "ecs_service" {
  source = "../.."

  name = module.context.prefix
  tags = module.context.tags

  cluster_arn  = "arn:aws:ecs:eu-west-1:333333333333:cluster/meridian-prod-compute"
  cluster_name = "meridian-prod-compute"

  vpc_id         = "vpc-0123456789abcdef0"
  vpc_cidr_block = "10.30.0.0/16"
  subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1", "subnet-0123456789abcdef2"]

  image = "333333333333.dkr.ecr.eu-west-1.amazonaws.com/meridian-prod-catalog:589969013abb"

  execution_role_arn = "arn:aws:iam::333333333333:role/meridian-prod-catalog-execution-role"
  task_role_arn      = "arn:aws:iam::333333333333:role/meridian-prod-catalog-task-role"

  listener_arn                    = "arn:aws:elasticloadbalancing:eu-west-1:333333333333:listener/app/meridian-prod-compute/0123456789abcdef/0123456789abcdef"
  listener_rule_priority          = 100
  path_patterns                   = ["/catalog", "/catalog/*"]
  health_check_path               = "/catalog/healthz"
  load_balancer_security_group_id = "sg-0123456789abcdef0"

  # The catalog service uses the catalog database and nothing else.
  data_access = {
    postgresql = { security_group_id = "sg-0123456789abcdef1", port = 5432 }
  }

  environment = { LOG_LEVEL = "info" }
  secrets = {
    PARTNER_TOKEN = "arn:aws:secretsmanager:eu-west-1:333333333333:secret:/meridian/prod/catalog/secrets/partner-api-token-AbCdEf"
  }

  log_group_name   = "${module.context.ssm_path}/ecs"
  logs_kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
}
