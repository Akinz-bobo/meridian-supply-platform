#!/usr/bin/env bash
# Builds a service's container image and pushes it to the service's
# repository in an environment.
#
# Usage: push-image.sh <environment-directory> <service>
# Prints the full image reference on the last line.
#
# The tag is the content of the service's directory: a hash of every file
# that goes into the image. The same source always gets the same tag, so
# running this twice pushes once, and a tag always means one exact build.
# Tags are immutable in the registry, so this is also the only scheme that
# does not fail on the second run.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_dir="$root/infra/environments/$1"
service="$2"
source_dir="$root/services/$service"

[ -f "$source_dir/Dockerfile" ] || { echo "No Dockerfile in services/$service." >&2; exit 1; }

hcl_value() { sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"/\1/p" "$2"; }

environment="$(hcl_value environment "$env_dir/env.tfvars")"
account="$(hcl_value aws_account_id "$env_dir/env.tfvars")"
region="$(hcl_value aws_region "$env_dir/env.tfvars")"

export AWS_DEFAULT_REGION="$region" AWS_PAGER=''
export AWS_ACCESS_KEY_ID="$account" AWS_SECRET_ACCESS_KEY=emulator

repository="$(aws ssm get-parameter --name "/meridian/$environment/$service/repository-url" --output json |
  jq -r '.Parameter.Value')"
name="${repository##*/}"

# Everything the image is built from, in a stable order. Files the
# .dockerignore leaves out do not change the image, so they do not change
# the tag.
tag="$(cd "$source_dir" && find . -type f -not -path './tests/*' -not -name '*.pyc' -not -path '*/__pycache__/*' \
  -not -name README.md -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12)"
image="$repository:$tag"

if aws ecr describe-images --repository-name "$name" --image-ids "imageTag=$tag" >/dev/null 2>&1; then
  echo "$service $tag is already in the registry." >&2
  echo "$image"
  exit 0
fi

echo "Building $service $tag." >&2
docker build --quiet --tag "$image" --label "org.opencontainers.image.revision=$tag" "$source_dir" >&2

# Where the image is pushed. On AWS it is the repository's own address. The
# emulator serves the ECR API on one port and the registry itself from a
# container on another, with repositories named <account>/<region>/<name>,
# and Docker refuses to speak plain HTTP to the first. So against the
# emulator the push goes to the registry container directly. The image is
# the same, and the ECR API lists it either way. See emulator difference 29.
target="$image"
if [ -n "${AWS_ENDPOINT_URL:-}" ] && [ "${TARGET:-emulator}" != aws ]; then
  target="localhost:${FLOCI_ECR_PORT:-5100}/$account/$region/$name:$tag"
  docker tag "$image" "$target"
else
  # The password goes from one command to the other through a pipe. It is
  # never an argument, where it would be visible in the process list.
  aws ecr get-login-password | docker login --username AWS --password-stdin "${repository%%/*}" >/dev/null 2>&1
fi

echo "Pushing $target." >&2
docker push --quiet "$target" >&2

# Confirm through the ECR API, which is what a deployment will use.
aws ecr describe-images --repository-name "$name" --image-ids "imageTag=$tag" >/dev/null ||
  { echo "The image was pushed and the registry does not list it." >&2; exit 1; }

echo "$image"
