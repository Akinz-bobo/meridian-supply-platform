#!/usr/bin/env bash
# Checks that the access rule given to a cache user limits a client the way
# the design says it does.
#
# Usage: cache-acl-check.sh <environment-directory>
#
# The rule is read from ElastiCache, so it is the one really applied to the
# environment, and loaded into a throwaway Valkey server of the same major
# version. A client is then connected as that user and tries what it should
# and should not be able to do.
#
# This tests the rule, not ElastiCache: that ElastiCache applies the rule,
# and that only the right IAM role can become the user, cannot be checked
# on the emulator.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_dir="$root/infra/environments/$1"

hcl_value() { sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"/\1/p" "$2"; }

environment="$(hcl_value environment "$env_dir/env.tfvars")"
account="$(hcl_value aws_account_id "$env_dir/env.tfvars")"
region="$(hcl_value aws_region "$env_dir/env.tfvars")"

export AWS_DEFAULT_REGION="$region" AWS_PAGER=''
export AWS_ACCESS_KEY_ID="$account" AWS_SECRET_ACCESS_KEY=emulator

user="meridian-$environment-inventory-cache-inventory"
image=valkey/valkey:8

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

echo "Cache access check: $1 (user $user)"

described="$(aws elasticache describe-users --user-id "$user" --output json | jq -c '.Users[0]')"
rule="$(jq -r '.AccessString' <<<"$described")"

check 'the user exists and authenticates with IAM, not a password' \
  jq -e '.Authentication.Type == "iam" and .Authentication.PasswordCount == 0' <<<"$described"
check 'the user belongs to the cache user group' \
  jq -e --arg g "meridian-$environment-inventory-cache" '.UserGroupIds | index($g) != null' <<<"$described"

container="meridian-acl-check-$$"
cleanup() { docker rm --force "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker run --detach --rm --name "$container" "$image" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  docker exec "$container" valkey-cli PING >/dev/null 2>&1 && break
  timeout 1 tail -f /dev/null || true
done

# The rule from ElastiCache, plus a password that exists only in this
# throwaway server. On ElastiCache the user proves who it is with IAM.
# shellcheck disable=SC2086 # the rule is several words, one per argument
docker exec "$container" valkey-cli ACL SETUSER client $rule '>check-only' >/dev/null

# as_client <command...>: runs a command as the limited user.
as_client() { docker exec "$container" valkey-cli --user client --pass check-only --no-auth-warning "$@"; }
allowed() { ! as_client "$@" | grep -q -E '^\(error\)|NOPERM|ERR'; }
denied() { as_client "$@" | grep -q NOPERM; }

check 'the client can connect' allowed PING
check 'it can write a key under stock:' allowed SET stock:SKU-1:LOS1 70
check 'it can read that key back' test "$(as_client GET stock:SKU-1:LOS1)" = 70
check 'it can set an expiry, as a cache does' allowed EXPIRE stock:SKU-1:LOS1 300
check 'it can delete a key under stock:' allowed DEL stock:SKU-1:LOS1
check 'it cannot write a key outside stock:' denied SET session:abc 1
check 'it cannot read a key outside stock:' denied GET budget:2031
check 'it cannot list every key' denied KEYS '*'
check 'it cannot empty the cache' denied FLUSHALL
check 'it cannot read or change the server configuration' denied CONFIG GET maxmemory
check 'it cannot manage users' denied ACL LIST
check 'it cannot shut the server down' denied SHUTDOWN NOSAVE
check 'it cannot run a script that would bypass the key pattern' denied EVAL "return redis.call('KEYS','*')" 0

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
