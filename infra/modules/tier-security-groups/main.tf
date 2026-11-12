# One security group per network tier, with rules that refer to each other
# by group and not by address range.
#
# The chain is: internet -> load balancer -> application -> data. Each link
# is a pair of rules, egress on one group and ingress on the next, so the
# path is visible from either end. Nothing else is allowed. In particular
# the data group has no egress rule at all.

locals {
  # All application ports as one map, so each port is its own rule and
  # adding a port never replaces an existing rule.
  app_ports  = { for port in var.app_ports : tostring(port) => port }
  lb_ports   = { for port in var.load_balancer_ports : tostring(port) => port }
  lb_sources = toset(var.load_balancer_ingress_cidrs)

  # Every combination of listener port and allowed source range.
  lb_ingress = {
    for pair in setproduct(keys(local.lb_ports), local.lb_sources) :
    "${pair[0]}-${pair[1]}" => { port = local.lb_ports[pair[0]], cidr = pair[1] }
  }
}

resource "aws_security_group" "load_balancer" {
  name        = "${var.name}-lb"
  description = "Load balancers. The only group that accepts traffic from outside the VPC."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-lb", Tier = "public" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "application" {
  name        = "${var.name}-app"
  description = "Workloads. Reached only from load balancers and from each other."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-app", Tier = "private" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "data" {
  name        = "${var.name}-data"
  description = "Databases and caches. Reached only from workloads. No outbound access."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-data", Tier = "data" })

  lifecycle {
    create_before_destroy = true
  }
}

# Internet -> load balancer

resource "aws_vpc_security_group_ingress_rule" "load_balancer_from_clients" {
  for_each = local.lb_ingress

  security_group_id = aws_security_group.load_balancer.id
  description       = "Clients to listener port ${each.value.port}"
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port

  tags = var.tags
}

# Load balancer -> application

resource "aws_vpc_security_group_egress_rule" "load_balancer_to_application" {
  for_each = local.app_ports

  security_group_id            = aws_security_group.load_balancer.id
  description                  = "To workloads on port ${each.value}"
  referenced_security_group_id = aws_security_group.application.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "application_from_load_balancer" {
  for_each = local.app_ports

  security_group_id            = aws_security_group.application.id
  description                  = "From load balancers on port ${each.value}"
  referenced_security_group_id = aws_security_group.load_balancer.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value

  tags = var.tags
}

# Application <-> application

resource "aws_vpc_security_group_ingress_rule" "application_from_application" {
  security_group_id            = aws_security_group.application.id
  description                  = "Between workloads, any port"
  referenced_security_group_id = aws_security_group.application.id
  ip_protocol                  = "-1"

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "application_to_application" {
  security_group_id            = aws_security_group.application.id
  description                  = "Between workloads, any port"
  referenced_security_group_id = aws_security_group.application.id
  ip_protocol                  = "-1"

  tags = var.tags
}

# Application -> data

resource "aws_vpc_security_group_egress_rule" "application_to_data" {
  for_each = var.data_ports

  security_group_id            = aws_security_group.application.id
  description                  = "To ${each.key} on port ${each.value}"
  referenced_security_group_id = aws_security_group.data.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "data_from_application" {
  for_each = var.data_ports

  security_group_id            = aws_security_group.data.id
  description                  = "From workloads to ${each.key} on port ${each.value}"
  referenced_security_group_id = aws_security_group.application.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value

  tags = var.tags
}

# Replication between members of the data tier, on the same ports.
resource "aws_vpc_security_group_ingress_rule" "data_from_data" {
  for_each = var.data_ports

  security_group_id            = aws_security_group.data.id
  description                  = "Replication between ${each.key} nodes on port ${each.value}"
  referenced_security_group_id = aws_security_group.data.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value

  tags = var.tags
}

# Application -> outside. HTTPS only: AWS APIs through endpoints or NAT,
# and partner APIs through NAT.
resource "aws_vpc_security_group_egress_rule" "application_to_https" {
  security_group_id = aws_security_group.application.id
  description       = "HTTPS to AWS services and partner APIs"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = var.tags
}

# Name resolution inside the VPC. The resolver is reached over UDP and,
# for large answers, TCP.
resource "aws_vpc_security_group_egress_rule" "application_to_dns" {
  for_each = toset(["udp", "tcp"])

  security_group_id = aws_security_group.application.id
  description       = "DNS to the VPC resolver over ${each.key}"
  cidr_ipv4         = var.vpc_cidr_block
  ip_protocol       = each.key
  from_port         = 53
  to_port           = 53

  tags = var.tags
}
