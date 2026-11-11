#!/usr/bin/env bash
# Generates the README of every module from its code, or checks that the
# committed READMEs are up to date.
#
# Usage: terraform-docs.sh [--check]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root/infra/.terraform-docs.yml"
mode="${1:-write}"
failed=0

for dir in "$root"/infra/modules/*/; do
  dir="${dir%/}"
  name="$(basename "$dir")"

  if [ ! -f "$dir/README.md" ]; then
    printf '  FAIL  %s has no README.md. Create one with: scripts/new-module.sh\n' "$name"
    failed=1
    continue
  fi
  if [ ! -f "$dir/examples/basic/main.tf" ]; then
    printf '  FAIL  %s has no examples/basic/main.tf\n' "$name"
    failed=1
    continue
  fi

  # The description above the generated section is written by hand. The
  # skeleton from new-module.sh marks it TODO until someone has.
  if grep --quiet '^TODO' "$dir/README.md"; then
    printf '  FAIL  %s: README.md still has the TODO placeholder for its description\n' "$name"
    failed=1
    continue
  fi

  if [ "$mode" = --check ]; then
    if terraform-docs --config "$config" --output-check "$dir" >/dev/null 2>&1; then
      printf '  ok    %s\n' "$name"
    else
      printf '  FAIL  %s: README.md is out of date. Run: make docs\n' "$name"
      failed=1
    fi
  else
    terraform-docs --config "$config" "$dir" >/dev/null
    printf '  wrote %s/README.md\n' "$name"
  fi
done

exit "$failed"
