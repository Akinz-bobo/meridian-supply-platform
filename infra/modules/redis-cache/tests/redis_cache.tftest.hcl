# Plan-only tests. The provider is real with placeholder credentials so the
# rendered connect policy can be read. Nothing is called: no AWS account or
# emulator is needed.

provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  name                = "meridian-prod-inventory-cache"
  description         = "Read cache of stock availability."
  account_id          = "333333333333"
  data_classification = "internal"
  subnet_ids          = ["subnet-data-a", "subnet-data-b", "subnet-data-c"]
  security_group_ids  = ["sg-data"]
  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
  logs_kms_key_arn    = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
  log_group_name      = "/meridian/prod/inventory/cache/slow-log"
  users = {
    inventory = {
      access_string = "on ~stock:* +@read +@write +@connection -@dangerous"
    }
  }
  tags = {
    Project = "meridian"
  }
}

run "is_encrypted_at_rest_and_in_transit" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.at_rest_encryption_enabled == "true" && aws_elasticache_replication_group.this.kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
    error_message = "The cache must be encrypted at rest with the key that was passed."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.transit_encryption_enabled
    error_message = "Connections to the cache must be encrypted."
  }
}

run "has_no_shared_password" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.auth_token == null && aws_elasticache_replication_group.this.auth_token_wo == null
    error_message = "The cache must not use an auth token. Clients authenticate as IAM users."
  }

  assert {
    condition     = one(aws_elasticache_user.this["inventory"].authentication_mode).type == "iam"
    error_message = "Every user authenticates with IAM."
  }

  assert {
    condition     = aws_elasticache_user.this["inventory"].user_id == aws_elasticache_user.this["inventory"].user_name
    error_message = "With IAM authentication the user name must equal the user id."
  }
}

run "admits_only_the_named_users" {
  command = plan

  assert {
    condition     = aws_elasticache_user_group.this.user_ids == toset(["meridian-prod-inventory-cache-inventory"])
    error_message = "The user group must contain the named users and nothing else."
  }

  assert {
    condition     = aws_elasticache_user.this["inventory"].access_string == "on ~stock:* +@read +@write +@connection -@dangerous"
    error_message = "A user gets exactly the access string it was given."
  }
}

run "fails_over_to_a_replica_by_default" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.num_cache_clusters == 2
    error_message = "The default is a primary and one replica."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.automatic_failover_enabled && aws_elasticache_replication_group.this.multi_az_enabled
    error_message = "With a replica, failover must be automatic and across zones."
  }
}

run "a_single_node_has_no_failover_to_turn_on" {
  command = plan

  variables {
    replicas = 0
  }

  assert {
    condition     = aws_elasticache_replication_group.this.num_cache_clusters == 1 && aws_elasticache_replication_group.this.automatic_failover_enabled == false
    error_message = "With no replica there is one node and no failover."
  }
}

run "evicts_when_full" {
  command = plan

  assert {
    condition     = one(aws_elasticache_parameter_group.this.parameter).value == "allkeys-lru"
    error_message = "A full cache must evict the least recently used key by default."
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.family == "valkey8"
    error_message = "The parameter group family follows the engine's major version."
  }
}

run "logs_slow_commands_to_an_encrypted_group_with_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.slow.retention_in_days == 90 && aws_cloudwatch_log_group.slow.kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
    error_message = "The slow log group needs retention and the logs key."
  }

  assert {
    condition     = one(aws_elasticache_replication_group.this.log_delivery_configuration).log_type == "slow-log"
    error_message = "The slow log must be delivered."
  }
}

run "keeps_a_final_snapshot_only_when_snapshots_are_on" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.final_snapshot_identifier == "meridian-prod-inventory-cache-final"
    error_message = "With snapshots on, a final snapshot is taken."
  }
}

run "a_cache_without_snapshots_takes_no_final_snapshot" {
  command = plan

  variables {
    snapshot_retention_days = 0
  }

  assert {
    condition     = aws_elasticache_replication_group.this.final_snapshot_identifier == null
    error_message = "With snapshots off there is no final snapshot."
  }
}

run "carries_its_classification_as_a_tag" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.tags["DataClassification"] == "internal"
    error_message = "The classification must become the DataClassification tag."
  }
}

run "a_client_may_connect_as_its_own_user_only" {
  command = plan

  assert {
    condition = toset(jsondecode(output.connect_policy_json["inventory"]).Statement[0].Resource) == toset([
      "arn:aws:elasticache:eu-west-1:333333333333:replicationgroup:meridian-prod-inventory-cache",
      "arn:aws:elasticache:eu-west-1:333333333333:user:meridian-prod-inventory-cache-inventory",
    ])
    error_message = "The connect policy must name this cache and this one user."
  }

  assert {
    condition     = jsondecode(output.connect_policy_json["inventory"]).Statement[0].Action == "elasticache:Connect"
    error_message = "The connect policy grants connecting and nothing else."
  }
}

run "rejects_a_user_with_every_command" {
  command = plan

  variables {
    users = {
      inventory = { access_string = "on ~stock:* +@all" }
    }
  }

  expect_failures = [var.users]
}

run "rejects_a_user_with_every_key" {
  command = plan

  variables {
    users = {
      inventory = { access_string = "on ~* +@read" }
    }
  }

  expect_failures = [var.users]
}

run "rejects_a_user_with_dangerous_commands" {
  command = plan

  variables {
    users = {
      inventory = { access_string = "on ~stock:* +@read +@dangerous" }
    }
  }

  expect_failures = [var.users]
}

run "rejects_a_cache_nobody_can_use" {
  command = plan

  variables {
    users = {}
  }

  expect_failures = [var.users]
}

run "rejects_refusing_writes_when_full" {
  command = plan

  variables {
    eviction_policy = "noeviction"
  }

  expect_failures = [var.eviction_policy]
}

run "rejects_a_cache_without_a_customer_managed_key" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_an_old_engine" {
  command = plan

  variables {
    engine_version = "6.2"
  }

  expect_failures = [var.engine_version]
}
