#!/usr/bin/env bash
# Prints the state layers that exist for an environment, in apply order.
# Usage: layers.sh <environment-directory> [--reverse]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_dir="$root/infra/environments/$1"

# Apply order. A layer may depend only on layers before it. See
# docs/adr/0008-layered-state-per-environment.md.
order=(foundation data messaging compute services)

[ -d "$env_dir" ] || { echo "No such environment: $1" >&2; exit 1; }

existing=()
for layer in "${order[@]}"; do
  if [ -f "$env_dir/$layer/main.tf" ]; then
    existing+=("$layer")
  fi
done

if [ "${2:-}" = --reverse ]; then
  for ((i = ${#existing[@]} - 1; i >= 0; i--)); do echo "${existing[i]}"; done
else
  printf '%s\n' "${existing[@]}"
fi
