# POL-KMS: encryption keys rotate and cannot be deleted quickly.
#
# The standard is in docs/architecture/encryption.md.
package terraform.kms

import rego.v1

import data.lib.plan

minimum_deletion_window := 14

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_kms_key"
	not rc.change.after.enable_key_rotation == true
	msg := sprintf("POL-KMS-1: %s does not rotate. Set enable_key_rotation to true", [rc.address])
}

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_kms_key"
	days := rc.change.after.deletion_window_in_days
	is_number(days)
	days < minimum_deletion_window
	msg := sprintf(
		"POL-KMS-2: %s can be deleted after %d days. The minimum deletion window is %d",
		[rc.address, days, minimum_deletion_window],
	)
}
