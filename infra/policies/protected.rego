# POL-PROTECT: a plan may not delete or replace a resource that holds data,
# unless the deletion is listed as an approved exception.
#
# Deleting a database, a bucket or an encryption key is not undone by
# running apply again. Outside dev, it has to be a decision someone made
# and recorded, not a side effect of an unrelated change.
package terraform.protected

import rego.v1

import data.lib.plan

stateful := {
	"aws_db_instance",
	"aws_dynamodb_table",
	"aws_efs_file_system",
	"aws_elasticache_replication_group",
	"aws_kinesis_stream",
	"aws_kms_key",
	"aws_rds_cluster",
	"aws_s3_bucket",
	"aws_secretsmanager_secret",
}

# Environments where data is disposable.
disposable := {"dev"}

approved(rc) if {
	some exception in data.exceptions.protected_deletes
	exception.address == rc.address
	exception.environment == plan.environment
}

verb(rc) := "replace" if "create" in rc.change.actions

verb(rc) := "delete" if not "create" in rc.change.actions

deny contains msg if {
	some rc in plan.deleting
	rc.type in stateful
	not plan.environment in disposable
	not approved(rc)
	msg := sprintf(
		"POL-PROTECT-1: the plan would %s %s in %s. If that is intended, add it to infra/policies/data/exceptions.yaml with a reason",
		[verb(rc), rc.address, plan.environment],
	)
}

warn contains msg if {
	some rc in plan.deleting
	rc.type in stateful
	plan.environment in disposable
	msg := sprintf("POL-PROTECT-1: the plan would %s %s. Allowed in %s", [verb(rc), rc.address, plan.environment])
}

# An exception that matches nothing in the plan is stale and should be removed.
warn contains msg if {
	some exception in data.exceptions.protected_deletes
	exception.environment == plan.environment
	not exception.address in {rc.address | some rc in plan.deleting}
	msg := sprintf("POL-PROTECT-2: the exception for %s matches nothing in this plan. Remove it", [exception.address])
}
