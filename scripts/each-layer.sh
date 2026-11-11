#!/usr/bin/env bash
# Runs a make target against every layer of an environment.
#
# Usage: each-layer.sh <apply|destroy|plan|policy> <environment-directory>
#
# Layers are applied in dependency order and destroyed in the reverse order,
# so nothing is removed while something still depends on it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="$1"
env="$2"

order=()
if [ "$action" = destroy ]; then
  order=(--reverse)
fi

while IFS= read -r layer; do
  echo "== $action $env/$layer"
  make --no-print-directory -C "$root" "$action" ENV="$env" LAYER="$layer"
done < <("$root/scripts/layers.sh" "$env" "${order[@]}")
