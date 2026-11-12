package terraform.cache_test

import rego.v1

import data.lib.fixtures
import data.terraform.cache

good := {
	"replication_group_id": "meridian-prod-inventory-cache",
	"transit_encryption_enabled": true,
	"at_rest_encryption_enabled": "true",
	"user_group_ids": ["meridian-prod-inventory-cache"],
}

group(overrides) := fixtures.create("aws_elasticache_replication_group", "c", object.union(good, overrides))

test_allows_an_encrypted_cache_with_iam_users if {
	count(cache.deny) == 0 with input as fixtures.plan("prod", [group({})])
}

test_denies_plain_connections if {
	messages := cache.deny with input as fixtures.plan("prod", [group({"transit_encryption_enabled": false})])
	some msg in messages
	contains(msg, "POL-CACHE-1")
}

test_denies_no_encryption_at_rest if {
	messages := cache.deny with input as fixtures.plan("prod", [group({"at_rest_encryption_enabled": "false"})])
	some msg in messages
	contains(msg, "POL-CACHE-2")
}

test_denies_a_shared_auth_token if {
	messages := cache.deny with input as fixtures.plan("prod", [group({"auth_token": "a-long-shared-password"})])
	some msg in messages
	contains(msg, "POL-CACHE-3")
}

test_allows_an_iam_user if {
	rc := fixtures.create("aws_elasticache_user", "u", {"user_id": "x", "authentication_mode": [{"type": "iam"}]})
	count(cache.deny) == 0 with input as fixtures.plan("prod", [rc])
}

test_denies_a_user_with_a_password if {
	rc := fixtures.create("aws_elasticache_user", "u", {"user_id": "x", "authentication_mode": [{"type": "password"}]})
	messages := cache.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-CACHE-4")
}

test_denies_a_user_with_no_password_required if {
	rc := fixtures.create("aws_elasticache_user", "u", {
		"user_id": "x",
		"authentication_mode": [{"type": "no-password-required"}],
	})
	messages := cache.deny with input as fixtures.plan("prod", [rc])
	some msg in messages
	contains(msg, "POL-CACHE-4")
}
