#!/usr/bin/env bash
# Builds and pushes the image of every service to an environment's
# repositories, and records each as the image to deploy.
#
# Usage: push-images.sh <environment-directory>
#
# Run before the services layer is planned or applied: that layer deploys
# whatever image each service's parameter names. A service whose image for
# the current source is already in the registry is not rebuilt.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for service in "$root"/services/*/; do
  name="$(basename "$service")"
  echo "== image $1/$name"
  "$root/scripts/push-image.sh" "$1" "$name"
done
