#!/usr/bin/env bash
# Runs `terraform validate` in every state layer and every module.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

while IFS= read -r dir; do
  label="${dir#"$root"/}"
  # Both steps write to the same variable, so a failure always shows the
  # output of the step that failed and never that of an earlier directory.
  if output="$(terraform -chdir="$dir" init -backend=false -input=false -no-color 2>&1)" &&
    output="$(terraform -chdir="$dir" validate -no-color 2>&1)"; then
    printf '  ok    %s\n' "$label"
  else
    printf '  FAIL  %s\n' "$label"
    printf '%s\n' "$output" | sed 's/^/        /'
    failed=1
  fi
done < <(
  # A directory is a Terraform root or module if it has a main.tf, apart
  # from the shared files that are only ever used through links.
  find "$root/infra" -name main.tf -not -path '*/.terraform/*' -not -path '*/_shared/*' -printf '%h\n' | sort
)

exit "$failed"
