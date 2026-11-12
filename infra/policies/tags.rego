# POL-TAG: every taggable resource carries the standard tags.
#
# Tags are how cost is allocated, how ownership is found during an incident
# and how IAM conditions separate environments. A resource without them is
# invisible to all three.
package terraform.tags

import rego.v1

import data.lib.plan

required := {"Project", "Environment", "Component", "ManagedBy"}

# A resource type is taggable if its planned values include tags_all.
taggable(rc) if "tags_all" in object.keys(rc.change.after)

deny contains msg if {
	some rc in plan.changing
	taggable(rc)
	not plan.unknown(rc, "tags_all")
	tags := object.get(rc.change.after, "tags_all", {})
	missing := required - {key | some key, _ in tags}
	count(missing) > 0
	msg := sprintf(
		"POL-TAG-1: %s is missing required tags: %s",
		[rc.address, concat(", ", sort(missing))],
	)
}

deny contains msg if {
	some rc in plan.changing
	taggable(rc)
	value := rc.change.after.tags_all.ManagedBy
	value != "terraform"
	msg := sprintf("POL-TAG-2: %s has ManagedBy=%q. It must be \"terraform\"", [rc.address, value])
}

deny contains msg if {
	some rc in plan.changing
	taggable(rc)
	value := rc.change.after.tags_all.Environment
	value != plan.environment
	msg := sprintf(
		"POL-TAG-3: %s is tagged Environment=%q but is being applied to %q",
		[rc.address, value, plan.environment],
	)
}

# Tags that depend on a value only known at apply cannot be verified here.
warn contains msg if {
	some rc in plan.changing
	taggable(rc)
	plan.unknown(rc, "tags_all")
	msg := sprintf("POL-TAG-1: tags on %s are not known until apply and were not checked", [rc.address])
}

# Stores that hold data. Each one says how sensitive its contents are, which
# decides who may read it, how long it is kept and whether it is backed up.
data_stores := {
	"aws_db_instance",
	"aws_dynamodb_table",
	"aws_efs_file_system",
	"aws_elasticache_replication_group",
	"aws_kinesis_stream",
	"aws_rds_cluster",
	"aws_s3_bucket",
}

classifications := {"public", "internal", "confidential", "restricted"}

deny contains msg if {
	some rc in plan.changing
	rc.type in data_stores
	not plan.unknown(rc, "tags_all")
	value := object.get(rc.change.after, ["tags_all", "DataClassification"], "")
	not value in classifications
	msg := sprintf(
		"POL-TAG-4: %s holds data and has DataClassification=%q. It must be one of: %s",
		[rc.address, value, concat(", ", sort(classifications))],
	)
}
