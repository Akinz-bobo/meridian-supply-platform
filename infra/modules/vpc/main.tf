# A three-tier network across several availability zones.
#
# Public subnets hold load balancers and NAT gateways. Private subnets hold
# workloads and reach the internet only outbound, through NAT. Data subnets
# hold databases and caches and have no route to the internet at all: their
# route table contains the local route and nothing else, and no resource in
# this module can add one.
#
# The address plan is fixed by the module so every environment is laid out
# the same way. See docs/architecture/environments.md.

locals {
  # Zone letter (a, b, c) keyed to the zone name, used in names and as the
  # stable key of every per-zone resource. Keying by letter and not by list
  # position means removing a zone never renumbers the others.
  zones = { for zone in var.availability_zones : substr(zone, -1, 1) => zone }

  # Position of each zone decides its address range.
  zone_index = { for index, zone in var.availability_zones : substr(zone, -1, 1) => index }

  # In a /16: public x.x.0-2.0/24, private x.x.32,64,96.0/19, data
  # x.x.160-162.0/24. The gaps are left free for growth.
  public_cidrs  = { for letter, index in local.zone_index : letter => cidrsubnet(var.cidr_block, 8, index) }
  private_cidrs = { for letter, index in local.zone_index : letter => cidrsubnet(var.cidr_block, 3, index + 1) }
  data_cidrs    = { for letter, index in local.zone_index : letter => cidrsubnet(var.cidr_block, 8, 160 + index) }

  # One NAT gateway in the first zone, or one in every zone.
  nat_zones = var.single_nat_gateway ? { (keys(local.zones)[0]) = values(local.zones)[0] } : local.zones
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name })
}

# The default security group cannot be deleted. Adopting it with no rules
# means anything launched without an explicit group can talk to nothing.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-default-unused" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = var.name })
}

# Public tier

resource "aws_subnet" "public" {
  for_each = local.zones

  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = local.public_cidrs[each.key]

  # Nothing in a public subnet gets a public address by accident. Load
  # balancers and NAT gateways bring their own.
  map_public_ip_on_launch = false

  tags = merge(var.tags, var.public_subnet_tags, {
    Name = "${var.name}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-public", Tier = "public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = local.zones

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

# NAT

resource "aws_eip" "nat" {
  for_each = local.nat_zones

  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_zones

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

# Private tier

resource "aws_subnet" "private" {
  for_each = local.zones

  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = local.private_cidrs[each.key]

  tags = merge(var.tags, var.private_subnet_tags, {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  })
}

# One route table per zone, so each zone can leave through its own NAT
# gateway and losing a zone does not cut off the others.
resource "aws_route_table" "private" {
  for_each = local.zones

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-private-${each.key}", Tier = "private" })
}

resource "aws_route" "private_nat" {
  for_each = local.zones

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"

  # With a single NAT gateway every zone uses the one that exists.
  nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? keys(local.nat_zones)[0] : each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = local.zones

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

# Data tier

resource "aws_subnet" "data" {
  for_each = local.zones

  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = local.data_cidrs[each.key]

  tags = merge(var.tags, {
    Name = "${var.name}-data-${each.key}"
    Tier = "data"
  })
}

# No aws_route is ever attached to this table. The local route that AWS adds
# to every table is the only one, so the data tier can reach the VPC and
# nothing else.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-data", Tier = "data" })
}

resource "aws_route_table_association" "data" {
  for_each = local.zones

  subnet_id      = aws_subnet.data[each.key].id
  route_table_id = aws_route_table.data.id
}

# A second barrier in front of the data tier. Security groups are the main
# control, and they are stateful and easy to open by mistake. This stateless
# list only lets the private tier in, whatever a security group says.
resource "aws_network_acl" "data" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for subnet in aws_subnet.data : subnet.id]

  tags = merge(var.tags, { Name = "${var.name}-data", Tier = "data" })
}

resource "aws_network_acl_rule" "data_in_from_private" {
  for_each = local.zone_index

  network_acl_id = aws_network_acl.data.id
  rule_number    = 100 + each.value
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.private_cidrs[each.key]
  from_port      = 0
  to_port        = 65535
}

# Replication between database instances in different zones.
resource "aws_network_acl_rule" "data_in_from_data" {
  for_each = local.zone_index

  network_acl_id = aws_network_acl.data.id
  rule_number    = 200 + each.value
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.data_cidrs[each.key]
  from_port      = 0
  to_port        = 65535
}

# Replies only. A network ACL is stateless, so return traffic to the VPC
# must be allowed explicitly. Nothing outside the VPC is reachable.
resource "aws_network_acl_rule" "data_out_to_vpc" {
  network_acl_id = aws_network_acl.data.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.cidr_block
  from_port      = 0
  to_port        = 65535
}
