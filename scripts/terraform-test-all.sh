#!/usr/bin/env bash
# Runs `terraform test` in every module that has a tests directory.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0
found=0

while IFS= read -r dir; do
  found=1
  label="${dir#"$root"/}"
  echo "== $label"
  terraform -chdir="$dir" init -backend=false -input=false >/dev/null
  terraform -chdir="$dir" test -no-color || failed=1
done < <(find "$root/infra/modules" -type d -name tests -not -path '*/.terraform/*' -printf '%h\n' | sort)

if [ "$found" = 0 ]; then
  echo 'No module tests found.'
fi
exit "$failed"
