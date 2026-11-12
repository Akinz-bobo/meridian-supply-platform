#!/usr/bin/env bash
# Checks that an applied environment looks the way it should, by asking the
# AWS API and not Terraform.
#
# Usage: smoke-test.sh <environment-directory>
#
# The jq programs in this file are single-quoted on purpose: $e, $a and $t
# are jq variables set with --arg, not shell variables.
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_dir="$root/infra/environments/$1"
shared="$root/infra/environments/_shared"

# hcl_value <key> <file>: the quoted string assigned to <key> in an HCL file.
hcl_value() { sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"/\1/p" "$2"; }

environment="$(hcl_value environment "$env_dir/env.tfvars")"
account="$(hcl_value aws_account_id "$env_dir/env.tfvars")"
region="$(hcl_value aws_region "$env_dir/env.tfvars")"
state_bucket="$(hcl_value bucket "$shared/backend.hcl")"
state_account="$(hcl_value access_key "$shared/backend.emulator.hcl")"

export AWS_DEFAULT_REGION="$region" AWS_PAGER=''

# Against the emulator the account is selected by the access key.
as_account() { AWS_ACCESS_KEY_ID="$1" AWS_SECRET_ACCESS_KEY=emulator "${@:2}"; }

passed=0
failed=0
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

echo "Smoke test: $1 ($environment, account $account)"

parameter="/meridian/$environment/platform/environment"
value="$(as_account "$account" aws ssm get-parameter --name "$parameter" --output json 2>/dev/null |
  jq -r '.Parameter.Value // empty' || true)"

check "the environment parameter exists at $parameter" test -n "$value"
check 'it records this environment' jq -e --arg e "$environment" '.environment == $e' <<<"$value"
check 'it records the account it was applied to' jq -e --arg a "$account" '.account_id == $a' <<<"$value"

tags="$(as_account "$account" aws ssm list-tags-for-resource --resource-type Parameter \
  --resource-id "$parameter" --output json 2>/dev/null || echo '{}')"
for tag in Project Environment Component ManagedBy; do
  check "it carries the $tag tag" jq -e --arg t "$tag" '[.TagList[]?.Key] | index($t) != null' <<<"$tags"
done

# Network: ask the EC2 API what was built, starting from the published VPC id.
network="/meridian/$environment/network"
vpc_id="$(as_account "$account" aws ssm get-parameter --name "$network/vpc-id" --output json 2>/dev/null |
  jq -r '.Parameter.Value // empty' || true)"
check "the VPC id is published at $network/vpc-id" test -n "$vpc_id"

subnets="$(as_account "$account" aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" \
  --output json 2>/dev/null || echo '{}')"
for tier in public private data; do
  check "the $tier tier has a subnet in each of three zones" jq -e --arg t "$tier" \
    '[.Subnets[]? | select(any(.Tags[]?; .Key == "Tier" and .Value == $t)) | .AvailabilityZone] | unique | length == 3' \
    <<<"$subnets"
done
check 'no subnet assigns public addresses on launch' \
  jq -e '[.Subnets[]? | select(.MapPublicIpOnLaunch)] | length == 0' <<<"$subnets"

routes="$(as_account "$account" aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" \
  --output json 2>/dev/null || echo '{}')"
data_table='.RouteTables[]? | select(any(.Tags[]?; .Key == "Tier" and .Value == "data"))'
check 'the data route table is associated with three subnets' \
  jq -e "[$data_table | .Associations[]?] | length == 3" <<<"$routes"
check 'the data tier has no route out of the VPC' \
  jq -e "[$data_table | .Routes[]? | (.GatewayId // \"\") as \$g
    | select(\$g != \"local\" and (\$g | startswith(\"vpce-\") | not))] | length == 0" <<<"$routes"
check 'every private route table leaves through a NAT gateway' jq -e \
  '[.RouteTables[]? | select(any(.Tags[]?; .Key == "Tier" and .Value == "private"))
    | any(.Routes[]?; .DestinationCidrBlock == "0.0.0.0/0" and .NatGatewayId != null)] | length == 3 and all' \
  <<<"$routes"

endpoints="$(as_account "$account" aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc_id" \
  --output json 2>/dev/null || echo '{}')"
for service in s3 dynamodb; do
  check "a gateway endpoint for $service is attached to the private and data route tables" jq -e --arg s "$service" \
    '[.VpcEndpoints[]? | select(.VpcEndpointType == "Gateway" and (.ServiceName | endswith("." + $s)))
      | .RouteTableIds | length] == [4]' <<<"$endpoints"
done
check 'every interface endpoint has private DNS and an interface in three zones' jq -e \
  '[.VpcEndpoints[]? | select(.VpcEndpointType == "Interface")] as $i
    | ($i | length) > 0 and ($i | all(.PrivateDnsEnabled and (.SubnetIds | length) == 3))' <<<"$endpoints"

flow_logs="$(as_account "$account" aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$vpc_id" \
  --output json 2>/dev/null || echo '{}')"
check 'a flow log records all traffic in the VPC' \
  jq -e '[.FlowLogs[]? | select(.TrafficType == "ALL" and .FlowLogStatus == "ACTIVE")] | length == 1' <<<"$flow_logs"
log_group="/meridian/$environment/network/flow-logs"
check "the flow log group $log_group has a retention period" jq -e --arg g "$log_group" \
  '[.logGroups[]? | select(.logGroupName == $g) | .retentionInDays] | length == 1 and all(. >= 30)' \
  <<<"$(as_account "$account" aws logs describe-log-groups --log-group-name-prefix "$log_group" --output json 2>/dev/null || echo '{}')"

while IFS= read -r layer; do
  check "state for the $layer layer is in the shared bucket" \
    as_account "$state_account" aws s3api head-object --bucket "$state_bucket" --key "$1/$layer/terraform.tfstate"
done < <("$root/scripts/layers.sh" "$1")

# Isolation: another environment's account must not be able to read this one's parameter.
not_visible_from() {
  ! as_account "$1" aws ssm get-parameter --name "$parameter"
}
for other in "$root"/infra/environments/*/env.tfvars; do
  other_account="$(hcl_value aws_account_id "$other")"
  if [ "$other_account" != "$account" ]; then
    check "the parameter is not visible from account $other_account" not_visible_from "$other_account"
  fi
done

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
