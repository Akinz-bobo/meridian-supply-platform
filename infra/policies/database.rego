# POL-DB: relational databases are private, encrypted, backed up and hold
# no password that Terraform knows.
#
# The postgres-database module already guarantees these. The policy is for
# a database created any other way.
package terraform.database

import rego.v1

import data.lib.plan

types := {"aws_db_instance", "aws_rds_cluster"}

# Environments where data is disposable.
disposable := {"dev"}

minimum_backup_days := 7

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_db_instance"
	rc.change.after.publicly_accessible == true
	msg := sprintf("POL-DB-1: %s is publicly accessible. A database is reached from the private subnets only", [rc.address])
}

deny contains msg if {
	some rc in plan.changing
	rc.type in types
	not rc.change.after.storage_encrypted == true
	msg := sprintf("POL-DB-2: %s is not encrypted at rest. Set storage_encrypted and the data key", [rc.address])
}

# A password given to Terraform is in state. RDS can manage it instead.
deny contains msg if {
	some rc in plan.changing
	rc.type in types
	some attribute in ["password", "master_password"]
	given(rc, attribute)
	msg := sprintf(
		"POL-DB-3: %s is given a master password. Set manage_master_user_password so that RDS creates and rotates it",
		[rc.address],
	)
}

given(rc, attribute) if {
	value := rc.change.after[attribute]
	is_string(value)
	value != ""
}

given(rc, attribute) if plan.unknown(rc, attribute)

deny contains msg if {
	some rc in plan.changing
	rc.type in types
	not plan.environment in disposable
	days := object.get(rc.change.after, "backup_retention_period", 0)
	days < minimum_backup_days
	msg := sprintf(
		"POL-DB-4: %s keeps backups for %d days. Outside dev the minimum is %d",
		[rc.address, days, minimum_backup_days],
	)
}

deny contains msg if {
	some rc in plan.changing
	rc.type in types
	not plan.environment in disposable
	not rc.change.after.deletion_protection == true
	not lifting_protection
	msg := sprintf("POL-DB-5: %s has no deletion protection. Outside dev it is required", [rc.address])
}

# A teardown lifts protections on purpose, by marking the environment
# disposable for that run. See docs/guides/pipeline.md.
lifting_protection if input.variables.disposable.value == true
