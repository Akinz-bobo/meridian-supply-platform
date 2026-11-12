#!/usr/bin/env bash
# Checks that the backup plan of an applied environment selects the right
# stores and that a backup of one lands in the vault.
#
# Usage: backup-check.sh <environment-directory>
#
# The plan selects by tag, so the first question is which resources carry
# the tag: the stores that should be backed up, and nothing else. The
# second is whether the backup service's role can take a backup, which is
# answered by taking one of the movement ledger.
#
# The recovery point is left in the vault. Deleting one by hand is what the
# vault's policy forbids.
#
# The jq programs in this file are single-quoted on purpose: $a is a jq
# variable set with --arg, not a shell variable.
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

vault="meridian-$environment-backup"
ledger="arn:aws:dynamodb:$region:$account:table/meridian-$environment-inventory-movements"
database="arn:aws:rds:$region:$account:db:meridian-$environment-catalog-db"

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

tagged() { # <resource arn> <tags as JSON list>
  jq -e 'any(.[]; .Key == "Backup" and .Value == "daily")' <<<"$2"
}

echo "Backup check: $1 (vault $vault)"

check 'the movement ledger carries the backup tag' tagged "$ledger" \
  "$(aws dynamodb list-tags-of-resource --resource-arn "$ledger" --output json | jq -c '.Tags')"
check 'the catalog database carries the backup tag' tagged "$database" \
  "$(aws rds list-tags-for-resource --resource-name "$database" --output json | jq -c '.TagList')"

# Resources around a store must not carry the tag, or the plan would try to
# back them up. The database's log group is the one that once did.
log_group="/aws/rds/instance/meridian-$environment-catalog-db/postgresql"
check 'the database log group does not carry the backup tag' jq -e 'has("Backup") | not' \
  <<<"$(aws logs list-tags-for-resource --output json \
    --resource-arn "arn:aws:logs:$region:$account:log-group:$log_group" | jq -c '.tags // {}')"
check 'the stock level table, which is rebuilt from the ledger, is not in the plan' jq -e \
  'any(.[]?; .Key == "Backup") | not' \
  <<<"$(aws dynamodb list-tags-of-resource --output json \
    --resource-arn "arn:aws:dynamodb:$region:$account:table/meridian-$environment-inventory-stock-levels" | jq -c '.Tags')"

before="$(aws backup list-recovery-points-by-backup-vault --backup-vault-name "$vault" --output json |
  jq '.RecoveryPoints | length')"
job="$(aws backup start-backup-job --backup-vault-name "$vault" --resource-arn "$ledger" \
  --iam-role-arn "arn:aws:iam::$account:role/$vault-role" --output json | jq -r '.BackupJobId')"
check 'a backup of the ledger can be started with the service role' test -n "$job"

state=''
for _ in $(seq 1 30); do
  state="$(aws backup describe-backup-job --backup-job-id "$job" --output json | jq -r '.State')"
  case "$state" in COMPLETED | FAILED | ABORTED | EXPIRED) break ;; esac
  timeout 2 tail -f /dev/null || true
done
check 'the backup job completes' test "$state" = COMPLETED

points="$(aws backup list-recovery-points-by-backup-vault --backup-vault-name "$vault" --output json)"
check 'a new recovery point is in the vault' test "$(jq '.RecoveryPoints | length' <<<"$points")" -gt "$before"
check 'the recovery point is a copy of the ledger' jq -e --arg a "$ledger" \
  'any(.RecoveryPoints[]; .ResourceArn == $a and .Status == "COMPLETED")' <<<"$points"

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
