# A Redis-compatible cache on ElastiCache, running Valkey.
#
# Always: in the given private subnets, encrypted at rest with a customer
# managed key, encrypted in transit, and with no shared password. Clients
# are named users that authenticate with their IAM role, each limited to
# the keys and commands it is given.
#
# By default, and reduced only where the environment is disposable: a
# replica in a second zone with automatic failover, and daily snapshots.

data "aws_region" "current" {}

locals {
  tags = merge(var.tags, { DataClassification = var.data_classification })

  ra = "${data.aws_region.current.region}:${var.account_id}"

  replicated = var.replicas > 0

  # With IAM authentication the user name must equal the user id.
  users = { for key, user in var.users : key => merge(user, { id = "${var.name}-${key}" }) }
}

resource "aws_elasticache_subnet_group" "this" {
  name        = var.name
  description = "Subnets of the data tier for ${var.name}."
  subnet_ids  = var.subnet_ids

  tags = var.tags
}

resource "aws_elasticache_parameter_group" "this" {
  name        = var.name
  family      = "valkey${split(".", var.engine_version)[0]}"
  description = "Parameters for ${var.name}."

  # This is a cache, not a store. When memory is full, the least recently
  # used key is evicted to make room. The default would refuse new writes.
  parameter {
    name  = "maxmemory-policy"
    value = var.eviction_policy
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# The only users are the ones named by the caller. A Valkey user group has
# no default user, so nothing can connect without being one of them. (A
# Redis OSS group must contain a user called default. Valkey dropped that
# requirement, and refuses a passwordless user in a group.)
resource "aws_elasticache_user" "this" {
  for_each = local.users

  user_id       = each.value.id
  user_name     = each.value.id
  engine        = "valkey"
  access_string = each.value.access_string

  # The client presents a short-lived token signed with its IAM role. There
  # is no password to store, leak or rotate.
  authentication_mode {
    type = "iam"
  }

  tags = var.tags
}

resource "aws_elasticache_user_group" "this" {
  user_group_id = var.name
  engine        = "valkey"
  user_ids      = [for user in aws_elasticache_user.this : user.user_id]

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "slow" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = var.description

  engine               = "valkey"
  engine_version       = var.engine_version
  node_type            = var.node_type
  parameter_group_name = aws_elasticache_parameter_group.this.name
  port                 = 6379

  # One primary and the given number of replicas, spread across zones. With
  # at least one replica, a failed primary is replaced automatically.
  num_cache_clusters         = 1 + var.replicas
  automatic_failover_enabled = local.replicated
  multi_az_enabled           = local.replicated

  # Network.
  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = var.security_group_ids

  # Encryption.
  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  transit_encryption_enabled = true

  # Access. No auth token: users authenticate with IAM.
  user_group_ids = [aws_elasticache_user_group.this.user_group_id]

  # Recovery. A cache can be rebuilt from its source, so snapshots exist to
  # make a restart warm, not to protect data.
  snapshot_retention_limit  = var.snapshot_retention_days
  snapshot_window           = var.snapshot_window
  final_snapshot_identifier = var.snapshot_retention_days > 0 ? "${var.name}-final" : null

  # Maintenance.
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  # Commands slower than the engine's threshold, to find the ones that
  # block everything else in a single-threaded server.
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.slow.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  tags = local.tags
}

# What a client's role needs in order to connect as one of the users.
data "aws_iam_policy_document" "connect" {
  for_each = local.users

  statement {
    sid     = "ConnectAsThisUser"
    actions = ["elasticache:Connect"]
    resources = [
      "arn:aws:elasticache:${local.ra}:replicationgroup:${var.name}",
      "arn:aws:elasticache:${local.ra}:user:${each.value.id}",
    ]
  }
}
