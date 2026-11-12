# The way in: one load balancer per environment, in the public subnets,
# with the load balancer security group from the foundation layer.

# Validated through DNS, by adding the records ACM asks for to the zone of
# the domain. The zone is not managed in this repository.
resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = module.context.tags

  lifecycle {
    # A certificate in use cannot be deleted. The replacement is created
    # first and the listener moves to it.
    create_before_destroy = true
  }
}

module "load_balancer" {
  source = "../../../modules/load-balancer"

  name = module.context.prefix
  tags = module.context.tags

  subnet_ids         = split(",", local.facts.public_subnet_ids)
  security_group_ids = [local.facts.load_balancer_security_group_id]
  certificate_arn    = aws_acm_certificate.this.arn

  deletion_protection = !var.disposable
}

resource "aws_ssm_parameter" "load_balancer" {
  for_each = {
    "load-balancer-arn"      = module.load_balancer.arn
    "load-balancer-dns-name" = module.load_balancer.dns_name
    "https-listener-arn"     = module.load_balancer.https_listener_arn
    "domain-name"            = var.domain_name
  }

  name        = "${module.context.ssm_path}/${each.key}"
  description = "Load balancer fact, published by the compute layer."
  type        = "String"
  value       = each.value

  tags = module.context.tags
}
