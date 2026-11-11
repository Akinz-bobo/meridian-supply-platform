#!/usr/bin/env bash
# Runs tflint in every state layer and every module.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root/.tflint.hcl"
failed=0

tflint --init --config="$config" >/dev/null

while IFS= read -r dir; do
  label="${dir#"$root"/}"
  if output="$(tflint --config="$config" --chdir="$dir" --minimum-failure-severity=warning 2>&1)"; then
    printf '  ok    %s\n' "$label"
  else
    printf '  FAIL  %s\n' "$label"
    printf '%s\n' "$output" | sed 's/^/        /'
    failed=1
  fi
done < <(
  # Examples are a single file showing how to call a module. They are
  # validated, but not held to the module structure rules.
  find "$root/infra" -name main.tf -not -path '*/.terraform/*' -not -path '*/_shared/*' \
    -not -path '*/examples/*' -printf '%h\n' | sort
)

exit "$failed"
