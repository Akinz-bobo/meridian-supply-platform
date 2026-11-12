# POL-LOG: logs are kept for a bounded, sufficient time.
#
# A log group with no retention keeps data, and is billed for it, forever.
# One with a very short retention is gone before an incident is noticed.
package terraform.logging

import rego.v1

import data.lib.plan

minimum_days := 30

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_cloudwatch_log_group"
	object.get(rc.change.after, "retention_in_days", 0) in {0, null}
	msg := sprintf("POL-LOG-1: %s has no retention period. Set retention_in_days", [rc.address])
}

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_cloudwatch_log_group"
	days := rc.change.after.retention_in_days
	is_number(days)
	days > 0
	days < minimum_days
	msg := sprintf(
		"POL-LOG-2: %s keeps logs for %d days. The minimum is %d",
		[rc.address, days, minimum_days],
	)
}

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_cloudwatch_log_group"
	not plan.unknown(rc, "kms_key_id")
	object.get(rc.change.after, "kms_key_id", null) in {"", null}
	msg := sprintf(
		"POL-LOG-3: %s is not encrypted with a customer managed key. Set kms_key_id to the logs key",
		[rc.address],
	)
}
