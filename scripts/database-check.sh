#!/usr/bin/env bash
# Connects to the catalog database of an applied environment and uses it.
#
# Usage: database-check.sh <environment-directory>
#
# Everything is discovered the way a service would discover it: the address,
# port and name from Parameter Store, and the credentials from the secret
# that RDS manages. Nothing is passed in and nothing is written down.
#
# The password travels in the PGPASSWORD variable of the psql process only.
# It is never printed, logged or put on a command line.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_dir="$root/infra/environments/$1"

hcl_value() { sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"/\1/p" "$2"; }

environment="$(hcl_value environment "$env_dir/env.tfvars")"
account="$(hcl_value aws_account_id "$env_dir/env.tfvars")"
region="$(hcl_value aws_region "$env_dir/env.tfvars")"

export AWS_DEFAULT_REGION="$region" AWS_PAGER=''
export AWS_ACCESS_KEY_ID="$account" AWS_SECRET_ACCESS_KEY=emulator

command -v psql >/dev/null || { echo 'psql is needed for the database check. Install the PostgreSQL client.' >&2; exit 1; }

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

parameter() {
  aws ssm get-parameter --name "/meridian/$environment/catalog/$1" --output json | jq -r '.Parameter.Value'
}

echo "Database check: $1 (catalog)"

address="$(parameter db-address)"
port="$(parameter db-port)"
database="$(parameter db-name)"
secret_arn="$(parameter db-master-secret-arn)"

check 'the address, port, name and secret are published' test -n "$address" -a -n "$port" -a -n "$database" -a -n "$secret_arn"

secret="$(aws secretsmanager get-secret-value --secret-id "$secret_arn" --output json | jq -r '.SecretString')"
username="$(jq -r '.username' <<<"$secret")"

check 'the master credentials are in a secret that RDS manages' \
  jq -e '(.password | length) >= 16 and (.username | length) > 0' <<<"$secret"
check 'the master user is not a guessable name' \
  jq -e '.username | IN("postgres", "admin", "root") | not' <<<"$secret"

# sql <statement>: runs one statement and prints the result unformatted.
sql() {
  PGPASSWORD="$(jq -r '.password' <<<"$secret")" PGCONNECT_TIMEOUT=10 \
    psql --host "$address" --port "$port" --username "$username" --dbname "$database" \
    --no-psqlrc --tuples-only --no-align --quiet --set ON_ERROR_STOP=1 --command "$1"
}

check 'a connection with those credentials succeeds' sql 'select 1'
check "the database is called $database" test "$(sql 'select current_database()')" = "$database"
check 'the engine is PostgreSQL 16' test "$(sql "select current_setting('server_version_num')::int / 10000")" = 16

# Use it: a table with a constraint, a transaction that is rolled back, and
# a clean-up. The schema is this script's own and is removed afterwards.
schema="check_$(date +%s)_$$"
cleanup() { sql "drop schema if exists $schema cascade" >/dev/null 2>&1 || true; }
trap cleanup EXIT

check 'a schema and a table with constraints can be created' sql "
  create schema $schema;
  create table $schema.product (
    sku text primary key,
    name text not null,
    shelf_life_days integer not null check (shelf_life_days > 0)
  );"
check 'a row can be written and read back' test "$(sql "
  insert into $schema.product values ('SKU-1', 'Yoghurt 500g', 21);
  select name from $schema.product where sku = 'SKU-1';")" = 'Yoghurt 500g'
refused() { ! "$@"; }
check 'a row that breaks a constraint is refused' refused sql "insert into $schema.product values ('SKU-2', 'Bad', 0)"
check 'a duplicate key is refused' refused sql "insert into $schema.product values ('SKU-1', 'Again', 5)"
check 'a failed transaction leaves nothing behind' test "$(sql "
  begin;
  insert into $schema.product values ('SKU-3', 'Milk 1l', 10);
  rollback;
  select count(*) from $schema.product;")" = 1

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
