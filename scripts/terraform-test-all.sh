#!/usr/bin/env bash
# Runs `terraform test` in every module.
#
# Usage: terraform-test-all.sh              plan tests, in each module's tests/
#        terraform-test-all.sh --emulator   apply tests, in tests-emulator/
#
# Plan tests need nothing. Apply tests create and destroy real resources in
# the emulator, so they need it running and AWS_ENDPOINT_URL set, which
# `make test-emulator` does.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
directory=tests
if [ "${1:-}" = --emulator ]; then
  directory=tests-emulator
  if [ -z "${AWS_ENDPOINT_URL:-}" ]; then
    echo 'Apply tests run against the emulator. Use: make test-emulator' >&2
    exit 1
  fi
fi

failed=0
found=0

while IFS= read -r dir; do
  found=1
  label="${dir#"$root"/}"
  echo "== $label"
  terraform -chdir="$dir" init -backend=false -input=false >/dev/null
  terraform -chdir="$dir" test -no-color -test-directory="$directory" || failed=1
done < <(find "$root/infra/modules" -type d -name "$directory" -not -path '*/.terraform/*' -printf '%h\n' | sort)

if [ "$found" = 0 ]; then
  echo "No module has a $directory directory."
fi
exit "$failed"
