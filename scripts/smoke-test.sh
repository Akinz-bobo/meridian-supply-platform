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

# Data layer: the catalog database.
database="$(as_account "$account" aws rds describe-db-instances \
  --db-instance-identifier "meridian-$environment-catalog-db" --output json 2>/dev/null |
  jq -c '.DBInstances[0] // {}' || echo '{}')"
check 'the catalog database is available' jq -e '.DBInstanceStatus == "available"' <<<"$database"
check 'it is not publicly accessible' jq -e '.PubliclyAccessible == false' <<<"$database"
check 'it is encrypted with the data key' jq -e --arg k "$data_key_arn" \
  '.StorageEncrypted and .KmsKeyId == $k' <<<"$database"
check 'its master password is managed by RDS' jq -e '.MasterUserSecret.SecretArn != null' <<<"$database"
check 'it is in the three data subnets' jq -e '.DBSubnetGroup.Subnets | length == 3' <<<"$database"
data_group="$(jq -r --arg p "$prefix" '.SecurityGroups[]? | select(.GroupName == $p + "-data") | .GroupId' <<<"$groups")"
check 'it carries the data security group and no other' jq -e --arg g "$data_group" \
  '[.VpcSecurityGroups[].VpcSecurityGroupId] == [$g]' <<<"$database"
check 'it takes automated backups' jq -e '.BackupRetentionPeriod >= 1' <<<"$database"
check 'it accepts IAM authentication' jq -e '.IAMDatabaseAuthenticationEnabled' <<<"$database"
check 'it exports its logs' jq -e '.EnabledCloudwatchLogsExports | index("postgresql") != null' <<<"$database"
if [ "$disposable" != true ]; then
  check 'it is protected from deletion' jq -e '.DeletionProtection' <<<"$database"
  check 'it has a standby in a second zone' jq -e '.MultiAZ' <<<"$database"
  check 'it keeps at least a week of backups' jq -e '.BackupRetentionPeriod >= 7' <<<"$database"
fi
check 'its parameter group requires TLS' jq -e \
  'any(.Parameters[]?; .ParameterName == "rds.force_ssl" and .ParameterValue == "1")' \
  <<<"$(as_account "$account" aws rds describe-db-parameters --db-parameter-group-name "meridian-$environment-catalog-db" --output json 2>/dev/null || echo '{}')"
check 'its log group has retention and the logs key' jq -e --arg k "$logs_key_arn" \
  '.logGroups[0] | .retentionInDays >= 30 and .kmsKeyId == $k' \
  <<<"$(as_account "$account" aws logs describe-log-groups --log-group-name-prefix "/aws/rds/instance/meridian-$environment-catalog-db/postgresql" --output json 2>/dev/null || echo '{}')"

# Data layer: the stock cache.
cache="$(as_account "$account" aws elasticache describe-replication-groups \
  --replication-group-id "meridian-$environment-inventory-cache" --output json 2>/dev/null |
  jq -c '.ReplicationGroups[0] // {}' || echo '{}')"
check 'the stock cache is available' jq -e '.Status == "available"' <<<"$cache"
check 'it is encrypted at rest with the data key' jq -e --arg k "$data_key_arn" \
  '.AtRestEncryptionEnabled and .KmsKeyId == $k' <<<"$cache"
check 'it encrypts connections' jq -e '.TransitEncryptionEnabled' <<<"$cache"
check 'it has no shared auth token' jq -e '.AuthTokenEnabled == false' <<<"$cache"
check 'it admits clients through its user group' jq -e --arg g "meridian-$environment-inventory-cache" \
  '.UserGroupIds == [$g]' <<<"$cache"
check 'every cache user authenticates with IAM' jq -e \
  '[.Users[]? | .Authentication.Type] | length > 0 and all(. == "iam")' \
  <<<"$(as_account "$account" aws elasticache describe-users --output json 2>/dev/null || echo '{}')"
if [ "$disposable" != true ]; then
  check 'it has a replica to fail over to' jq -e '(.MemberClusters | length) >= 2' <<<"$cache"
fi

# Data layer: backups.
vault="$(as_account "$account" aws backup describe-backup-vault --backup-vault-name "meridian-$environment-backup" \
  --output json 2>/dev/null || echo '{}')"
backup_key_arn="$(as_account "$account" aws kms describe-key --key-id "alias/meridian-$environment-backup" --output json \
  2>/dev/null | jq -r '.KeyMetadata.Arn // empty' || true)"
check 'the backup vault exists and is encrypted with its own key' jq -e --arg k "$backup_key_arn" \
  '.EncryptionKeyArn == $k and ($k | length) > 0' <<<"$vault"
check 'the vault policy forbids deleting a recovery point by hand' jq -e \
  '.Policy | fromjson | any(.Statement[]; .Effect == "Deny" and (.Action | index("backup:DeleteRecoveryPoint") != null))' \
  <<<"$(as_account "$account" aws backup get-backup-vault-access-policy --backup-vault-name "meridian-$environment-backup" --output json 2>/dev/null || echo '{}')"
if [ "$disposable" != true ]; then
  check 'the vault is locked with a minimum retention' jq -e '.Locked and .MinRetentionDays >= 7' <<<"$vault"
fi
plan_id="$(as_account "$account" aws ssm get-parameter --name "/meridian/$environment/backup/plan-id" --output json \
  2>/dev/null | jq -r '.Parameter.Value // empty' || true)"
check 'the backup plan runs daily and keeps backups for at least a week' jq -e \
  '.BackupPlan.Rules | length > 0 and all(.Lifecycle.DeleteAfterDays >= 7)' \
  <<<"$(as_account "$account" aws backup get-backup-plan --backup-plan-id "$plan_id" --output json 2>/dev/null || echo '{}')"
check 'the plan selects stores by tag' jq -e '.BackupSelectionsList | length == 1' \
  <<<"$(as_account "$account" aws backup list-backup-selections --backup-plan-id "$plan_id" --output json 2>/dev/null || echo '{}')"
check 'the backup role carries a boundary' jq -e \
  '.Role.PermissionsBoundary.PermissionsBoundaryArn | endswith("AWSBackupServiceRolePolicyForBackup")' \
  <<<"$(as_account "$account" aws iam get-role --role-name "meridian-$environment-backup-role" --output json 2>/dev/null || echo '{}')"

# Messaging layer: the event bus.
bus="meridian-$environment-events"
described_bus="$(as_account "$account" aws events describe-event-bus --name "$bus" --output json 2>/dev/null || echo '{}')"
check "the event bus $bus exists" jq -e --arg b "$bus" '.Name == $b' <<<"$described_bus"
check 'its policy refuses publishers from outside the account' jq -e --arg a "$account" \
  '.Policy | fromjson | any(.Statement[]; .Effect == "Deny" and .Action == "events:PutEvents"
    and .Condition.StringNotEquals["aws:PrincipalAccount"] == $a)' <<<"$described_bus"
check 'events are archived for replay' jq -e '.State == "ENABLED" and .RetentionDays >= 7' \
  <<<"$(as_account "$account" aws events describe-archive --archive-name "$bus" --output json 2>/dev/null || echo '{}')"
check 'a rule sends every platform event to the event log' jq -e \
  '.EventPattern | fromjson | .source[0].prefix == "meridian."' \
  <<<"$(as_account "$account" aws events describe-rule --name "$bus-log-all" --event-bus-name "$bus" --output json 2>/dev/null || echo '{}')"
check 'the event log has retention and the logs key' jq -e --arg k "$logs_key_arn" \
  '.logGroups[0] | .retentionInDays >= 30 and .kmsKeyId == $k' \
  <<<"$(as_account "$account" aws logs describe-log-groups --log-group-name-prefix "/aws/events/$bus" --output json 2>/dev/null || echo '{}')"
check 'the bus name is published for services' \
  as_account "$account" aws ssm get-parameter --name "/meridian/$environment/events/bus-name"

# Messaging layer: consumer queues.
messaging_key_arn="$(as_account "$account" aws kms describe-key --key-id "alias/meridian-$environment-messaging" \
  --output json 2>/dev/null | jq -r '.KeyMetadata.Arn // empty' || true)"
for consumer in inventory-product-published inventory-goods-received budget-goods-received; do
  queue="meridian-$environment-$consumer"
  url="$(as_account "$account" aws sqs get-queue-url --queue-name "$queue" --output json 2>/dev/null |
    jq -r '.QueueUrl // empty' || true)"
  attributes="$(as_account "$account" aws sqs get-queue-attributes --queue-url "$url" --attribute-names All \
    --output json 2>/dev/null | jq -c '.Attributes // {}' || echo '{}')"
  check "the queue $consumer exists and is encrypted with the messaging key" jq -e --arg k "$messaging_key_arn" \
    '.KmsMasterKeyId == $k' <<<"$attributes"
  check "it moves a message to $consumer-dlq after five failed receives" jq -e --arg d "$queue-dlq" \
    '.RedrivePolicy | fromjson | .maxReceiveCount == 5 and (.deadLetterTargetArn | endswith(":" + $d))' <<<"$attributes"
  check 'only its own rule on the bus can deliver to it' jq -e --arg r "rule/$bus/$queue" \
    '.Policy | fromjson | any(.Statement[]; .Effect == "Allow" and .Principal.Service == "events.amazonaws.com"
      and (.Condition.ArnEquals["aws:SourceArn"] | endswith($r)))' <<<"$attributes"
  check 'an event the bus cannot deliver is parked in its dead-letter queue' jq -e --arg d "$queue-dlq" \
    '.Targets[0] | (.DeadLetterConfig.Arn | endswith(":" + $d)) and .RetryPolicy.MaximumEventAgeInSeconds <= 86400' \
    <<<"$(as_account "$account" aws events list-targets-by-rule --rule "$queue" --event-bus-name "$bus" --output json 2>/dev/null || echo '{}')"
  check 'an alarm fires when its consumer falls behind' jq -e --arg q "$queue" \
    '.MetricAlarms[0] | .MetricName == "ApproximateAgeOfOldestMessage" and any(.Dimensions[]; .Name == "QueueName" and .Value == $q)' \
    <<<"$(as_account "$account" aws cloudwatch describe-alarms --alarm-names "$queue-backlog" --output json 2>/dev/null || echo '{}')"
  check 'an alarm watches its dead-letter queue' jq -e --arg d "$queue-dlq" \
    '.MetricAlarms[0] | .Threshold == 0 and any(.Dimensions[]; .Name == "QueueName" and .Value == $d)' \
    <<<"$(as_account "$account" aws cloudwatch describe-alarms --alarm-names "$queue-dlq-not-empty" --output json 2>/dev/null || echo '{}')"
done

# Messaging layer: topics.
for topic in alarms notifications; do
  topic_arn="arn:aws:sns:$region:$account:meridian-$environment-$topic"
  attributes="$(as_account "$account" aws sns get-topic-attributes --topic-arn "$topic_arn" --output json 2>/dev/null |
    jq -c '.Attributes // {}' || echo '{}')"
  check "the $topic topic exists and is encrypted with the messaging key" jq -e --arg k "$messaging_key_arn" \
    '.KmsMasterKeyId == $k' <<<"$attributes"
  check "the $topic topic refuses publishing without TLS" jq -e \
    '.Policy | fromjson | any(.Statement[]; .Effect == "Deny" and .Condition.Bool["aws:SecureTransport"] == "false")' \
    <<<"$attributes"
done
check 'only CloudWatch, for this account, may publish to the alarms topic' jq -e --arg a "$account" \
  '.Attributes.Policy | fromjson | [.Statement[] | select(.Effect == "Allow")]
    | length == 1 and .[0].Principal.Service == "cloudwatch.amazonaws.com"
      and .[0].Condition.StringEquals["aws:SourceAccount"] == $a' \
  <<<"$(as_account "$account" aws sns get-topic-attributes --topic-arn "arn:aws:sns:$region:$account:meridian-$environment-alarms" --output json 2>/dev/null || echo '{}')"
check 'every queue alarm notifies the alarms topic' jq -e --arg t "arn:aws:sns:$region:$account:meridian-$environment-alarms" \
  '[.MetricAlarms[] | select(.AlarmName | test("-(dlq-not-empty|backlog)$"))]
    | length >= 6 and all(.AlarmActions == [$t] and .OKActions == [$t])' \
  <<<"$(as_account "$account" aws cloudwatch describe-alarms --alarm-name-prefix "meridian-$environment-" --output json 2>/dev/null || echo '{}')"
check 'a rule sends notification events to the notifications topic' jq -e \
  '.Targets | length == 1 and (.[0].Arn | endswith("-notifications")) and .[0].InputPath == "$.detail"' \
  <<<"$(as_account "$account" aws events list-targets-by-rule --rule "meridian-$environment-notifications" --event-bus-name "$bus" --output json 2>/dev/null || echo '{}')"

# Messaging layer: the movement stream.
stream="$(as_account "$account" aws kinesis describe-stream-summary \
  --stream-name "meridian-$environment-inventory-movement-stream" --output json 2>/dev/null |
  jq -c '.StreamDescriptionSummary // {}' || echo '{}')"
check 'the movement stream is active' jq -e '.StreamStatus == "ACTIVE"' <<<"$stream"
check 'it is encrypted with the messaging key' jq -e --arg k "$messaging_key_arn" \
  '.EncryptionType == "KMS" and .KeyId == $k' <<<"$stream"
check 'it keeps records for three days' jq -e '.RetentionPeriodHours == 72' <<<"$stream"
check 'its name is published for the inventory service' \
  as_account "$account" aws ssm get-parameter --name "/meridian/$environment/inventory/movement-stream-name"

# Compute layer: the registry.
repository="$(as_account "$account" aws ecr describe-repositories --repository-names "meridian-$environment-sample" \
  --output json 2>/dev/null | jq -c '.repositories[0] // {}' || echo '{}')"
check 'the sample image repository exists' jq -e '.repositoryName != null' <<<"$repository"
check 'its tags cannot be overwritten' jq -e '.imageTagMutability == "IMMUTABLE"' <<<"$repository"
check 'it scans images when they are pushed' jq -e '.imageScanningConfiguration.scanOnPush' <<<"$repository"
check 'it is encrypted with the data key' jq -e --arg k "$data_key_arn" \
  '.encryptionConfiguration | .encryptionType == "KMS" and .kmsKey == $k' <<<"$repository"
check 'it removes untagged images and keeps a bounded number of tagged ones' jq -e \
  '.lifecyclePolicyText | fromjson | .rules | length == 2 and any(.selection.tagStatus == "untagged")' \
  <<<"$(as_account "$account" aws ecr get-lifecycle-policy --repository-name "meridian-$environment-sample" --output json 2>/dev/null || echo '{}')"

# Compute layer: the load balancer.
balancer="$(as_account "$account" aws elbv2 describe-load-balancers --names "meridian-$environment-compute" \
  --output json 2>/dev/null | jq -c '.LoadBalancers[0] // {}' || echo '{}')"
balancer_arn="$(jq -r '.LoadBalancerArn // empty' <<<"$balancer")"
check 'the load balancer is active' jq -e '.State.Code == "active" and .Type == "application"' <<<"$balancer"
lb_group="$(jq -r --arg p "$prefix" '.SecurityGroups[]? | select(.GroupName == $p + "-lb") | .GroupId' <<<"$groups")"
check 'it carries the load balancer security group and no other' jq -e --arg g "$lb_group" \
  '.SecurityGroups == [$g]' <<<"$balancer"
listeners="$(as_account "$account" aws elbv2 describe-listeners --load-balancer-arn "$balancer_arn" --output json \
  2>/dev/null || echo '{}')"
check 'its only listener is HTTPS on 443' jq -e \
  '[.Listeners[]? | [.Port, .Protocol]] == [[443, "HTTPS"]]' <<<"$listeners"
check 'the listener accepts TLS 1.2 and 1.3 only' jq -e \
  '.Listeners[0].SslPolicy | startswith("ELBSecurityPolicy-TLS13-")' <<<"$listeners"
check 'a request that matches no rule is refused by the load balancer' jq -e \
  '.Listeners[0].DefaultActions | length == 1 and .[0].Type == "fixed-response" and .[0].FixedResponseConfig.StatusCode == "404"' \
  <<<"$listeners"
attributes="$(as_account "$account" aws elbv2 describe-load-balancer-attributes --load-balancer-arn "$balancer_arn" \
  --output json 2>/dev/null | jq -c '[.Attributes[]? | {(.Key): .Value}] | add // {}' || echo '{}')"
check 'it drops malformed headers and ambiguous requests' jq -e \
  '.["routing.http.drop_invalid_header_fields.enabled"] == "true" and .["routing.http.desync_mitigation_mode"] == "strictest"' \
  <<<"$attributes"
if [ "$disposable" != true ]; then
  check 'it is protected from deletion' jq -e '.["deletion_protection.enabled"] == "true"' <<<"$attributes"
fi
domain="$(hcl_value domain_name "$env_dir/env.tfvars")"
check "a certificate is issued for $domain" jq -e --arg d "$domain" \
  'any(.CertificateSummaryList[]?; .DomainName == $d and .Status == "ISSUED")' \
  <<<"$(as_account "$account" aws acm list-certificates --output json 2>/dev/null || echo '{}')"

# Compute layer: the ECS cluster.
cluster="$(as_account "$account" aws ecs describe-clusters --clusters "meridian-$environment-compute" \
  --include SETTINGS CONFIGURATIONS --output json 2>/dev/null | jq -c '.clusters[0] // {}' || echo '{}')"
check 'the ECS cluster is active' jq -e '.status == "ACTIVE"' <<<"$cluster"
check 'it reports metrics per container' jq -e \
  'any(.settings[]?; .name == "containerInsights" and .value == "enabled")' <<<"$cluster"
check 'it records shell sessions, encrypted with the logs key' jq -e --arg k "$logs_key_arn" \
  '.configuration.executeCommandConfiguration | .logging == "OVERRIDE" and .kmsKeyId == $k
    and .logConfiguration.cloudWatchEncryptionEnabled' <<<"$cluster"

# Services layer: the sample service on ECS.
service="$(as_account "$account" aws ecs describe-services --cluster "meridian-$environment-compute" \
  --services "meridian-$environment-sample" --output json 2>/dev/null | jq -c '.services[0] // {}' || echo '{}')"
check 'the sample service is active and running the tasks it wants' jq -e \
  '.status == "ACTIVE" and .desiredCount >= 1 and .runningCount == .desiredCount' <<<"$service"
check 'its tasks have no public address' jq -e \
  '.networkConfiguration.awsvpcConfiguration.assignPublicIp == "DISABLED"' <<<"$service"
check 'a failed deployment is rolled back' jq -e \
  '.deploymentConfiguration.deploymentCircuitBreaker | .enable and .rollback' <<<"$service"
check 'a shell cannot be opened in its containers' jq -e '.enableExecuteCommand == false' <<<"$service"
definition="$(as_account "$account" aws ecs describe-task-definition --task-definition "meridian-$environment-sample" \
  --output json 2>/dev/null | jq -c '.taskDefinition // {}' || echo '{}')"
check 'its container is not root, cannot write to its filesystem and has no capabilities' jq -e \
  '.containerDefinitions[0] | .user == "10001:10001" and .readonlyRootFilesystem and (.privileged | not)
    and .linuxParameters.capabilities.drop == ["ALL"]' <<<"$definition"
deployed_image="$(as_account "$account" aws ssm get-parameter --name "/meridian/$environment/sample/image" \
  --output json 2>/dev/null | jq -r '.Parameter.Value // empty' || true)"
check 'it runs the image the release pointer names, by an exact tag' jq -e --arg i "$deployed_image" \
  '.containerDefinitions[0].image == $i and ($i | test(":[0-9a-f]{12}$"))' <<<"$definition"
check 'the role that starts it and the role it runs as are different' jq -e --arg e "$environment" \
  '(.executionRoleArn | endswith("meridian-" + $e + "-sample-execution-role"))
    and (.taskRoleArn | endswith("meridian-" + $e + "-sample-task-role"))' <<<"$definition"
for role in execution task; do
  check "its $role role carries the permission boundary" jq -e --arg b "$boundary_arn" \
    '.Role.PermissionsBoundary.PermissionsBoundaryArn == $b' \
    <<<"$(as_account "$account" aws iam get-role --role-name "meridian-$environment-sample-$role-role" --output json 2>/dev/null || echo '{}')"
done
check 'its task role has no permissions at all' jq -e '.PolicyNames == []' \
  <<<"$(as_account "$account" aws iam list-role-policies --role-name "meridian-$environment-sample-task-role" --output json 2>/dev/null || echo '{}')"
service_group="$(jq -c --arg n "meridian-$environment-sample" '.SecurityGroups[]? | select(.GroupName == $n)' <<<"$groups")"
check 'it has a security group of its own, reached only from the load balancer' jq -e --arg g "$lb_group" \
  '.IpPermissions | length == 1 and .[0].FromPort == 8080 and (.[0].IpRanges | length) == 0
    and [.[0].UserIdGroupPairs[].GroupId] == [$g]' <<<"$service_group"
check 'its target is healthy' jq -e \
  '.TargetHealthDescriptions | length >= 1 and all(.TargetHealth.State == "healthy")' \
  <<<"$(as_account "$account" aws elbv2 describe-target-health --output json --target-group-arn "$(as_account "$account" \
    aws elbv2 describe-target-groups --names "meridian-$environment-sample" --output json 2>/dev/null |
    jq -r '.TargetGroups[0].TargetGroupArn // empty')" 2>/dev/null || echo '{}')"

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
