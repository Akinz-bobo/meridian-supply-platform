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
  check "a gateway endpoint for $service is attached to the three private route tables" jq -e --arg s "$service" \
    '[.VpcEndpoints[]? | select(.VpcEndpointType == "Gateway" and (.ServiceName | endswith("." + $s)))
      | .RouteTableIds | length] == [3]' <<<"$endpoints"
  check "the $service endpoint reaches only this account's resources" jq -e --arg s "$service" --arg a "$account" \
    '.VpcEndpoints[]? | select(.VpcEndpointType == "Gateway" and (.ServiceName | endswith("." + $s)))
      | .PolicyDocument | fromjson | .Statement[0].Condition.StringEquals["aws:ResourceAccount"] == $a' <<<"$endpoints"
done
check "every endpoint admits only this account's principals" jq -e --arg a "$account" \
  '[.VpcEndpoints[]? | .PolicyDocument | fromjson | .Statement[]
    | .Condition.StringEquals["aws:PrincipalAccount"] == $a] | length > 0 and all' <<<"$endpoints"
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

groups="$(as_account "$account" aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" \
  --output json 2>/dev/null || echo '{}')"
prefix="meridian-$environment-network"
check 'the load balancer, application and data security groups exist' jq -e --arg p "$prefix" \
  '[.SecurityGroups[]?.GroupName] | contains([$p + "-lb", $p + "-app", $p + "-data"])' <<<"$groups"
check 'only the load balancer group accepts traffic from the internet' jq -e --arg p "$prefix" \
  '[.SecurityGroups[]? | select(any(.IpPermissions[]?.IpRanges[]?; .CidrIp == "0.0.0.0/0")) | .GroupName]
    == [$p + "-lb"]' <<<"$groups"
check 'the data group is reached by group reference only' jq -e --arg p "$prefix" \
  '.SecurityGroups[]? | select(.GroupName == $p + "-data") | .IpPermissions
    | length > 0 and all((.IpRanges | length) == 0 and (.UserIdGroupPairs | length) > 0)' <<<"$groups"
check 'the data group has no outbound rules' jq -e --arg p "$prefix" \
  '.SecurityGroups[]? | select(.GroupName == $p + "-data") | .IpPermissionsEgress | length == 0' <<<"$groups"
check 'the default security group has no rules' jq -e \
  '.SecurityGroups[]? | select(.GroupName == "default")
    | (.IpPermissions | length) == 0 and (.IpPermissionsEgress | length) == 0' <<<"$groups"

# Encryption keys.
for purpose in data logs messaging secrets; do
  alias="alias/meridian-$environment-$purpose"
  key_id="$(as_account "$account" aws kms describe-key --key-id "$alias" --output json 2>/dev/null |
    jq -r '.KeyMetadata | select(.Enabled) | .KeyId // empty' || true)"
  check "the $purpose key exists and is enabled as $alias" test -n "$key_id"
  check "the $purpose key rotates" jq -e '.KeyRotationEnabled' \
    <<<"$(as_account "$account" aws kms get-key-rotation-status --key-id "$key_id" --output json 2>/dev/null || echo '{}')"
done
logs_key_arn="$(as_account "$account" aws kms describe-key --key-id "alias/meridian-$environment-logs" --output json \
  2>/dev/null | jq -r '.KeyMetadata.Arn // empty' || true)"
check 'the flow log group is encrypted with the logs key' jq -e --arg g "$log_group" --arg k "$logs_key_arn" \
  '[.logGroups[]? | select(.logGroupName == $g) | .kmsKeyId] == [$k]' \
  <<<"$(as_account "$account" aws logs describe-log-groups --log-group-name-prefix "$log_group" --output json 2>/dev/null || echo '{}')"
check 'the logs key policy limits CloudWatch Logs to this account' jq -e --arg a "$account" \
  '.Policy | fromjson | .Statement[] | select(.Principal.Service != null)
    | .Condition.StringEquals["aws:SourceAccount"] == $a' \
  <<<"$(as_account "$account" aws kms get-key-policy --key-id "$logs_key_arn" --policy-name default --output json 2>/dev/null || echo '{}')"

# Identity and access.
boundary_arn="arn:aws:iam::$account:policy/meridian-$environment-workload-boundary"
check 'the workload permission boundary exists' \
  as_account "$account" aws iam get-policy --policy-arn "$boundary_arn"
check 'the flow logs delivery role carries the boundary' jq -e --arg b "$boundary_arn" \
  '.Role.PermissionsBoundary.PermissionsBoundaryArn == $b' \
  <<<"$(as_account "$account" aws iam get-role --role-name "meridian-$environment-network-flow-logs-role" --output json 2>/dev/null || echo '{}')"

deploy_trust="$(as_account "$account" aws iam get-role --role-name "meridian-$environment-access-deploy" \
  --output json 2>/dev/null | jq -c '.Role.AssumeRolePolicyDocument.Statement[0] // {}' || echo '{}')"
check 'the deploy role is assumed with a GitHub token, not a stored key' \
  jq -e '.Action == "sts:AssumeRoleWithWebIdentity" and (.Principal.Federated | endswith("token.actions.githubusercontent.com"))' \
  <<<"$deploy_trust"
check 'the deploy role names one repository and one environment' jq -e \
  '.Condition.StringEquals["token.actions.githubusercontent.com:sub"]
    | type == "string" and startswith("repo:") and (contains("*") | not)' <<<"$deploy_trust"
for role in operator audit; do
  check "the $role role requires multi-factor authentication" jq -e \
    '.Role.AssumeRolePolicyDocument.Statement[0].Condition.Bool["aws:MultiFactorAuthPresent"] == "true"' \
    <<<"$(as_account "$account" aws iam get-role --role-name "meridian-$environment-access-$role" --output json 2>/dev/null || echo '{}')"
done
check 'the audit role has only the audit and view-only policies' jq -e \
  '[.AttachedPolicies[]?.PolicyName] | sort == ["SecurityAudit", "ViewOnlyAccess"]' \
  <<<"$(as_account "$account" aws iam list-attached-role-policies --role-name "meridian-$environment-access-audit" --output json 2>/dev/null || echo '{}')"

# Account baseline.
check 'public buckets are blocked for the whole account' jq -e \
  '.PublicAccessBlockConfiguration | .BlockPublicAcls and .IgnorePublicAcls and .BlockPublicPolicy and .RestrictPublicBuckets' \
  <<<"$(as_account "$account" aws s3control get-public-access-block --account-id "$account" --output json 2>/dev/null || echo '{}')"
check 'new EBS volumes are encrypted by default' jq -e '.EbsEncryptionByDefault' \
  <<<"$(as_account "$account" aws ec2 get-ebs-encryption-by-default --output json 2>/dev/null || echo '{}')"
check 'an access analyzer is active' jq -e '[.analyzers[]? | select(.status == "ACTIVE")] | length == 1' \
  <<<"$(as_account "$account" aws accessanalyzer list-analyzers --output json 2>/dev/null || echo '{}')"

# Data layer: object storage.
data_key_arn="$(as_account "$account" aws kms describe-key --key-id "alias/meridian-$environment-data" --output json \
  2>/dev/null | jq -r '.KeyMetadata.Arn // empty' || true)"
uploads="meridian-$environment-catalog-uploads-$account-$region"
s3() { as_account "$account" aws s3api "$@" --bucket "$uploads" --output json 2>/dev/null || echo '{}'; }
check "the supplier uploads bucket $uploads exists" as_account "$account" aws s3api head-bucket --bucket "$uploads"
check 'it blocks every form of public access' jq -e \
  '.PublicAccessBlockConfiguration | .BlockPublicAcls and .IgnorePublicAcls and .BlockPublicPolicy and .RestrictPublicBuckets' \
  <<<"$(s3 get-public-access-block)"
check 'it keeps previous versions' jq -e '.Status == "Enabled"' <<<"$(s3 get-bucket-versioning)"
check 'it is encrypted by default with the data key' jq -e --arg k "$data_key_arn" \
  '.ServerSideEncryptionConfiguration.Rules[0]
    | .BucketKeyEnabled and .ApplyServerSideEncryptionByDefault.SSEAlgorithm == "aws:kms"
      and .ApplyServerSideEncryptionByDefault.KMSMasterKeyID == $k' <<<"$(s3 get-bucket-encryption)"
check 'its policy refuses requests without TLS' jq -e \
  '.Policy | fromjson | any(.Statement[]; .Effect == "Deny" and .Condition.Bool["aws:SecureTransport"] == "false")' \
  <<<"$(s3 get-bucket-policy)"
check 'it is classified as confidential' jq -e \
  'any(.TagSet[]?; .Key == "DataClassification" and .Value == "confidential")' <<<"$(s3 get-bucket-tagging)"
check 'it expires objects and old versions' jq -e \
  '.Rules[]? | select(.ID == "retention") | .Expiration.Days == 365 and .NoncurrentVersionExpiration.NoncurrentDays >= 7' \
  <<<"$(s3 get-bucket-lifecycle-configuration)"
check 'it sends object events to EventBridge' jq -e 'has("EventBridgeConfiguration")' \
  <<<"$(s3 get-bucket-notification-configuration)"
check 'its name is published for the catalog service' \
  as_account "$account" aws ssm get-parameter --name "/meridian/$environment/catalog/uploads-bucket-name"

# Data layer: tables.
disposable="$(sed -n 's/^disposable[[:space:]]*=[[:space:]]*\(true\|false\).*/\1/p' "$env_dir/env.tfvars")"
for table in movements stock-levels; do
  name="meridian-$environment-inventory-$table"
  described="$(as_account "$account" aws dynamodb describe-table --table-name "$name" --output json 2>/dev/null || echo '{}')"
  check "the $table table exists and is active" jq -e '.Table.TableStatus == "ACTIVE"' <<<"$described"
  check "the $table table is encrypted with the data key" jq -e --arg k "$data_key_arn" \
    '.Table.SSEDescription | .Status == "ENABLED" and .SSEType == "KMS" and .KMSMasterKeyArn == $k' <<<"$described"
  check "the $table table can be restored to a point in time" jq -e \
    '.ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus == "ENABLED"' \
    <<<"$(as_account "$account" aws dynamodb describe-continuous-backups --table-name "$name" --output json 2>/dev/null || echo '{}')"
  if [ "$disposable" != true ]; then
    check "the $table table is protected from deletion" jq -e '.Table.DeletionProtectionEnabled' <<<"$described"
  fi
done
check 'the movement ledger streams every new item' jq -e \
  '.Table.StreamSpecification | .StreamEnabled and .StreamViewType == "NEW_IMAGE"' \
  <<<"$(as_account "$account" aws dynamodb describe-table --table-name "meridian-$environment-inventory-movements" --output json 2>/dev/null || echo '{}')"
check 'the stock level table has its expiry and batch indexes' jq -e \
  '[.Table.GlobalSecondaryIndexes[]?.IndexName] | sort == ["by-batch", "by-expiry-date"]' \
  <<<"$(as_account "$account" aws dynamodb describe-table --table-name "meridian-$environment-inventory-stock-levels" --output json 2>/dev/null || echo '{}')"

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
