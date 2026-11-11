#!/usr/bin/env bash
# Runs `terraform validate` in every state layer and every module.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

while IFS= read -r dir; do
  label="${dir#"$root"/}"
  if terraform -chdir="$dir" init -backend=false -input=false >/dev/null 2>&1 &&
    output="$(terraform -chdir="$dir" validate -no-color 2>&1)"; then
    printf '  ok    %s\n' "$label"
  else
    printf '  FAIL  %s\n' "$label"
    printf '%s\n' "${output:-terraform init failed}" | sed 's/^/        /'
    failed=1
  fi
done < <(
  # A directory is a Terraform root or module if it has a main.tf, apart
  # from the shared files that are only ever used through links.
  find "$root/infra" -name main.tf -not -path '*/.terraform/*' -not -path '*/_shared/*' -printf '%h\n' | sort
)

exit "$failed"
