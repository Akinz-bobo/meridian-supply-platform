# POL-CACHE: caches are encrypted and have no shared password.
#
# The redis-cache module already guarantees these. The policy is for a
# cache created any other way.
package terraform.cache

import rego.v1

import data.lib.plan

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_elasticache_replication_group"
	not rc.change.after.transit_encryption_enabled == true
	msg := sprintf("POL-CACHE-1: %s does not encrypt connections. Set transit_encryption_enabled", [rc.address])
}

# The provider reports this attribute as a string.
deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_elasticache_replication_group"
	not rc.change.after.at_rest_encryption_enabled in {true, "true"}
	msg := sprintf("POL-CACHE-2: %s is not encrypted at rest. Set at_rest_encryption_enabled and the data key", [rc.address])
}

# An auth token is one password shared by every client, and it is stored
# in state. Named users that authenticate with IAM have neither problem.
deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_elasticache_replication_group"
	token_given(rc)
	msg := sprintf(
		"POL-CACHE-3: %s uses an auth token. Use a user group whose users authenticate with IAM",
		[rc.address],
	)
}

token_given(rc) if {
	value := rc.change.after.auth_token
	is_string(value)
	value != ""
}

token_given(rc) if plan.unknown(rc, "auth_token")

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_elasticache_user"
	some mode in object.get(rc.change.after, "authentication_mode", [])
	mode.type != "iam"
	msg := sprintf(
		"POL-CACHE-4: %s authenticates with %q. Cache users authenticate with IAM",
		[rc.address, mode.type],
	)
}
