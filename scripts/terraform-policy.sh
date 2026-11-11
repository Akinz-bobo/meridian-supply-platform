#!/usr/bin/env bash
# Plans one state layer and evaluates the plan against the policies.
#
# Usage: terraform-policy.sh <terraform-dir> [terraform plan arguments...]
# The directory must already be initialised (make init).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$1"
shift

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The plan file and its JSON form can contain secrets, so they live in a
# private temporary directory and are removed on exit.
terraform -chdir="$dir" plan -input=false -lock=false -out="$work/plan.bin" "$@" >/dev/null
terraform -chdir="$dir" show -json "$work/plan.bin" >"$work/plan.json"

conftest test \
  --policy "$root/infra/policies" \
  --data "$root/infra/policies/data" \
  --all-namespaces \
  "$work/plan.json"
