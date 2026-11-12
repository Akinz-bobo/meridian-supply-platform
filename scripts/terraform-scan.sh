#!/usr/bin/env bash
# Scans the Terraform for security misconfigurations.
#
# Usage: terraform-scan.sh [extra trivy arguments]
#
# Every environment layer shares its variable declarations through a
# symbolic link, and the scanner does not follow links. Scanned in place, a
# layer's variables are all unknown to it, so any setting that depends on
# one, such as deletion protection, is reported as missing or is not
# checked at all. This script scans a copy of the tree in which the links
# have been replaced by the files they point to.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# -h copies what a link points to. Provider binaries and state are left out.
tar --create --dereference --file - --directory "$root" \
  --exclude .terraform --exclude '*.tfstate*' --exclude '*.tfplan' \
  infra trivy.yaml .trivyignore.yaml | tar --extract --file - --directory "$work"

cd "$work"
trivy config --config trivy.yaml "$@" infra
