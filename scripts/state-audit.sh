#!/usr/bin/env bash
# Fails if the remote state of an environment holds a secret value.
#
# Usage: state-audit.sh <environment-directory>
#
# State is encrypted and access to it is limited, and it is still read by
# every plan and kept for 90 days in old versions. The platform's rule is
# that secret values do not go there at all: generated secrets are written
# through write-only arguments, and other secrets are set outside Terraform.
# This script checks the rule against what is really in the bucket.
#
# The jq program is single-quoted on purpose: $names is a jq variable.
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shared="$root/infra/environments/_shared"

hcl_value() { sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"/\1/p" "$2"; }

bucket="$(hcl_value bucket "$shared/backend.hcl")"
state_account="$(hcl_value access_key "$shared/backend.emulator.hcl")"
region="$(hcl_value region "$shared/backend.hcl")"

export AWS_DEFAULT_REGION="${region:-eu-west-1}" AWS_PAGER=''

# Attribute names that carry a secret value when they are set.
names='["auth_token","client_secret","master_password","password","private_key","secret_binary","secret_string","token"]'

# Lists every non-empty secret attribute in a state file as
# "<resource address> <attribute>". SecureString parameters are reported
# when their value is stored.
find_secrets='
  .resources[]?
  | select(.mode == "managed")
  | ([.module, .type + "." + .name] | map(select(. != null)) | join(".")) as $address
  | .type as $type
  | .instances[]?
  | .attributes as $a
  | (
      ($a | to_entries[]
        | select(.key as $k | $names | index($k))
        | select(.value != null and .value != "")
        | .key),
      (select($type == "aws_ssm_parameter" and $a.type == "SecureString"
        and $a.value != null and $a.value != "") | "value")
    )
  | "\($address) \(.)"
'

echo "State audit: $1"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

while IFS= read -r layer; do
  key="$1/$layer/terraform.tfstate"
  if ! AWS_ACCESS_KEY_ID="$state_account" AWS_SECRET_ACCESS_KEY=emulator \
    aws s3api get-object --bucket "$bucket" --key "$key" "$work/$layer.json" >/dev/null 2>&1; then
    printf '  FAIL  %s: the state could not be read from the bucket\n' "$layer"
    failed=1
    continue
  fi

  found="$(jq -r --argjson names "$names" "$find_secrets" "$work/$layer.json")"
  if [ -z "$found" ]; then
    printf '  ok    %s: no secret values in state (%s resources)\n' "$layer" \
      "$(jq '[.resources[]? | select(.mode == "managed")] | length' "$work/$layer.json")"
  else
    printf '  FAIL  %s: secret values are stored in state\n' "$layer"
    printf '%s\n' "$found" | sed 's/^/          /'
    failed=1
  fi
done < <("$root/scripts/layers.sh" "$1")

exit "$failed"
