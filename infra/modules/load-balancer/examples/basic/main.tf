module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "compute"
}

module "load_balancer" {
  source = "../.."

  name = module.context.prefix
  tags = module.context.tags

  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1", "subnet-0123456789abcdef2"]
  security_group_ids = ["sg-0123456789abcdef0"]
  certificate_arn    = "arn:aws:acm:eu-west-1:333333333333:certificate/11111111-2222-3333-4444-555555555555"
}
