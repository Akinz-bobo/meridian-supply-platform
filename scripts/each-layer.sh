#!/usr/bin/env bash
# Runs a make target against every layer of an environment.
#
# Usage: each-layer.sh <apply|destroy|plan|policy> <environment-directory>
#
# Layers are applied in dependency order and destroyed in the reverse order,
# so nothing is removed while something still depends on it. Before the
# services layer is applied, each service's image is built and pushed.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="$1"
env="$2"

order=()
if [ "$action" = destroy ]; then
  order=(--reverse)
fi

while IFS= read -r layer; do
  # The services layer deploys images, so they must be in the registry
  # first, and the registry is created by the layer before. Building is
  # skipped when the image for the current source is already there.
  if [ "$action" = apply ] && [ "$layer" = services ]; then
    "$root/scripts/push-images.sh" "$env"
  fi

  echo "== $action $env/$layer"
  make --no-print-directory -C "$root" "$action" ENV="$env" LAYER="$layer"
done < <("$root/scripts/layers.sh" "$env" "${order[@]}")
