#!/usr/bin/env bash
# Calls the workloads of an applied environment the way a client would.
#
# Usage: compute-check.sh <environment-directory>
#
# The compute layer makes promises: the load balancer serves TLS and
# nothing else, refuses what no rule matches, and sends a service's paths
# to that service. The service that answers is the image that was
# deployed, in the environment it was deployed to, and gives away no
# credential. This script makes real requests and checks the answers.
#
# One hop is checked in parts on the emulator, which forwards from a load
# balancer to a target group only in its default account (emulator
# difference 34). Where the load balancer does forward, as on AWS, the
# request is checked end to end and the parts are not needed.
#
# The jq programs in this file are single-quoted on purpose: $e and the
# like are jq variables set with --arg, not shell variables.
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_dir="$root/infra/environments/$1"

hcl_value() { sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"/\1/p" "$2"; }

environment="$(hcl_value environment "$env_dir/env.tfvars")"
account="$(hcl_value aws_account_id "$env_dir/env.tfvars")"
region="$(hcl_value aws_region "$env_dir/env.tfvars")"

export AWS_DEFAULT_REGION="$region" AWS_PAGER=''
export AWS_ACCESS_KEY_ID="$account" AWS_SECRET_ACCESS_KEY=emulator

passed=0
failed=0
skipped=0
check() {
  local description=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  ok    %s\n' "$description"
    passed=$((passed + 1))
  else
    printf '  FAIL  %s\n' "$description"
    failed=$((failed + 1))
  fi
}
skip() { # <description> <reason>
  printf '  skip  %s (%s)\n' "$1" "$2"
  skipped=$((skipped + 1))
}

parameter() { aws ssm get-parameter --name "/meridian/$environment/$1" --output json | jq -r '.Parameter.Value'; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

balancer="$(parameter compute/load-balancer-dns-name)"
port="${FLOCI_HTTPS_PORT:-8443}"

# through <path>: a request to the load balancer over TLS. The emulator
# serves every load balancer on one local port and tells them apart by host
# name, so the name is resolved to the local address. The certificate is
# the emulator's own and is not verified. Prints the status, and leaves
# the body in $work/body.
through() {
  curl --silent --insecure --max-time 10 --resolve "$balancer:$port:127.0.0.1" \
    --output "$work/body" --write-out '%{http_code}' "https://$balancer:$port$1" || true
}

echo "Compute check: $1 (load balancer $balancer)"

status="$(through /nothing-is-routed-here)"
check 'the load balancer answers over TLS' test -n "$status" -a "$status" != 000
check 'a path that no rule matches is refused by the load balancer' test "$status" = 404
check 'with its own fixed answer, not a service' jq -e '.error == "not found"' "$work/body"
check 'plain HTTP to the same port is refused' test "$(curl --silent --max-time 5 --output /dev/null \
  --write-out '%{http_code}' --resolve "$balancer:$port:127.0.0.1" "http://$balancer:$port/" || true)" = 000

# The sample service on ECS.
image="$(parameter sample/image)"
tag="${image##*:}"
group="$(aws elbv2 describe-target-groups --names "meridian-$environment-sample" --output json |
  jq -r '.TargetGroups[0].TargetGroupArn')"
targets="$(aws elbv2 describe-target-health --target-group-arn "$group" --output json)"
check 'the sample service has a healthy target behind the load balancer' jq -e \
  '.TargetHealthDescriptions | length >= 1 and all(.TargetHealth.State == "healthy")' <<<"$targets"

status="$(through /sample/)"
check "the load balancer has a rule for the service's path" test "$status" != 404

# describes <file>: the answer is the sample service, in this environment,
# on ECS, at the version that was deployed.
describes() {
  jq -e --arg e "$environment" --arg v "$tag" \
    '.service == "sample" and .environment == $e and .platform == "ecs" and .version == $v' "$1"
}

if [ "$status" = 200 ]; then
  check 'a request through the load balancer is answered by the deployed service' describes "$work/body"
  call() { through "/sample$1" >/dev/null && cat "$work/body"; }
else
  skip 'a request through the load balancer is answered by the deployed service' \
    "the load balancer answered $status: the emulator forwards only in its default account, difference 34"
  # The remaining hop, checked directly: the address the load balancer
  # holds as its healthy target.
  target="$(jq -r '.TargetHealthDescriptions[0].Target | "\(.Id):\(.Port)"' <<<"$targets")"
  call() { curl --silent --max-time 10 "http://$target/sample$1"; }
  call / >"$work/direct" || true
  check 'the registered target answers as the deployed service' describes "$work/direct"
fi

check 'its health endpoint answers' jq -e '.status == "ok"' <<<"$(call /healthz)"
identity="$(call /identity)"
check 'it says how it obtains credentials' jq -e \
  '.source | IN("ecs-task-role", "eks-pod-identity", "environment-variables")' <<<"$identity"
check 'and gives away no key, secret or token' jq -e \
  'keys == ["credentials", "role", "source"] and (tostring | test("AKIA|ASIA|SecretAccessKey|Token") | not)' <<<"$identity"
check 'a path the service does not have is not found' jq -e '.error == "not found"' <<<"$(call /admin)"

# What ECS says is running is what the release pointer names.
running="$(aws ecs describe-tasks --cluster "meridian-$environment-compute" --output json --tasks "$(aws ecs list-tasks \
  --cluster "meridian-$environment-compute" --service-name "meridian-$environment-sample" --output json |
  jq -r '.taskArns[0]')" | jq -r '.tasks[0].containers[0].image')"
check 'the running task uses the image the release pointer names' test "$running" = "$image"

echo "$passed passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
