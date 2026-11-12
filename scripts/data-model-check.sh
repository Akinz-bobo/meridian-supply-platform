#!/usr/bin/env bash
# Exercises the inventory tables' key design against an applied environment.
#
# Usage: data-model-check.sh <environment-directory>
#
# The design in docs/architecture/inventory-data-model.md makes promises:
# a movement is recorded once however often it is sent, stock never goes
# negative, the batch that expires first is found first, and each index
# answers one question. This script writes a few items under a product code
# of its own, checks every promise through the DynamoDB API, and removes
# what it wrote.
#
# The expressions below are single-quoted on purpose: #q and :d are DynamoDB
# placeholders, not shell variables.
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

movements="meridian-$environment-inventory-movements"
levels="meridian-$environment-inventory-stock-levels"

# A product code no real product has, different on every run.
sku="CHECK-$(date +%s)-$$"
warehouse=LOS1
day=2031-03-04
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

level_key() { # <batch> <expiry> <zone>
  jq -cn --arg s "$sku" --arg w "$warehouse" --arg b "$1" --arg e "$2" --arg z "$3" \
    '{pk: {S: ("PRODUCT#" + $s)}, sk: {S: ("WH#" + $w + "#EXP#" + $e + "#BATCH#" + $b + "#ZONE#" + $z)}}'
}

# record <movement-id> <time> <batch> <expiry> <zone> <signed quantity>
#
# One transaction, three writes: a marker that makes the movement id unique,
# the movement itself, and the change to the stock level. Either all three
# happen or none does. A removal carries a condition that enough stock is
# there.
record() {
  local id=$1 at=$2 batch=$3 expiry=$4 zone=$5 quantity=$6
  local key update condition names values
  key="$(level_key "$batch" "$expiry" "$zone")"
  names='{"#q": "quantity"}'
  if [ "$quantity" -ge 0 ]; then
    update='ADD #q :d SET gsi1pk = :e, gsi1sk = :es, gsi2pk = :b, gsi2sk = :bs'
    condition=null
    values="$(jq -cn --arg d "$quantity" --arg e "EXP#$expiry" --arg es "PRODUCT#$sku#BATCH#$batch" \
      --arg b "BATCH#$batch" --arg bs "WH#$warehouse#ZONE#$zone" \
      '{":d": {N: $d}, ":e": {S: $e}, ":es": {S: $es}, ":b": {S: $b}, ":bs": {S: $bs}}')"
  else
    update='ADD #q :d'
    condition='"#q >= :need"'
    values="$(jq -cn --arg d "$quantity" --arg n "$((-quantity))" '{":d": {N: $d}, ":need": {N: $n}}')"
  fi

  jq -cn --arg m "$movements" --arg l "$levels" --arg id "$id" --arg at "$at" --arg batch "$batch" \
    --arg w "$warehouse" --arg day "$day" --arg q "$quantity" --arg sku "$sku" \
    --argjson key "$key" --arg update "$update" --argjson condition "$condition" \
    --argjson names "$names" --argjson values "$values" '
    [
      {Put: {TableName: $m,
        Item: {pk: {S: ("MOVEMENT#" + $id)}, sk: {S: "MOVEMENT"}},
        ConditionExpression: "attribute_not_exists(pk)"}},
      {Put: {TableName: $m,
        Item: {pk: {S: ("BATCH#" + $batch)}, sk: {S: ("MOVE#" + $at + "#" + $id)},
          gsi1pk: {S: ("WH#" + $w + "#DAY#" + $day)}, gsi1sk: {S: ($at + "#" + $id)},
          product: {S: $sku}, quantity: {N: $q}}}},
      {Update: ({TableName: $l, Key: $key, UpdateExpression: $update,
          ExpressionAttributeNames: $names, ExpressionAttributeValues: $values}
        + (if $condition == null then {} else {ConditionExpression: $condition} end))}
    ]' >"$work/transaction.json"
  aws dynamodb transact-write-items --transact-items "file://$work/transaction.json"
}

quantity_of() { # <batch> <expiry> <zone>
  aws dynamodb get-item --table-name "$levels" --key "$(level_key "$@")" --consistent-read --output json |
    jq -r '.Item.quantity.N // "none"'
}

refused() { ! "$@"; }

cleanup() {
  for table in "$movements" "$levels"; do
    # A scan is acceptable here: it is a clean-up of this script's own items
    # in a test run, not an access pattern of the service.
    aws dynamodb scan --table-name "$table" --output json \
      --filter-expression 'contains(pk, :s) OR contains(sk, :s) OR product = :p OR begins_with(pk, :m)' \
      --expression-attribute-values "$(jq -cn --arg s "$sku" --arg m "MOVEMENT#$sku" '{":s": {S: $s}, ":p": {S: $s}, ":m": {S: $m}}')" \
      2>/dev/null | jq -c '.Items[]? | {pk, sk}' | while IFS= read -r key; do
      aws dynamodb delete-item --table-name "$table" --key "$key" >/dev/null 2>&1 || true
    done
  done
  rm -rf "$work"
}
work="$(mktemp -d)"
trap cleanup EXIT

echo "Data model check: $1 (product $sku)"

late="B-$sku-LATE"
early="B-$sku-EARLY"

# Receive two batches. The one received second expires first.
check 'a receipt creates the stock level' record "$sku-1" "${day}T08:00:00Z" "$late" 2031-09-30 CHILL-A 100
check 'the level holds the received quantity' test "$(quantity_of "$late" 2031-09-30 CHILL-A)" = 100
check 'a second batch is received' record "$sku-2" "${day}T09:00:00Z" "$early" 2031-06-15 CHILL-B 40

# INV-6, and exactly-once recording.
check 'the same movement sent twice is refused' refused record "$sku-1" "${day}T08:00:00Z" "$late" 2031-09-30 CHILL-A 100
check 'and the stock level is unchanged by the replay' test "$(quantity_of "$late" 2031-09-30 CHILL-A)" = 100

# INV-5: never negative.
check 'a pick within the stock on hand succeeds' record "$sku-3" "${day}T10:00:00Z" "$late" 2031-09-30 CHILL-A -30
check 'the level is reduced' test "$(quantity_of "$late" 2031-09-30 CHILL-A)" = 70
check 'a pick of more than is on hand is refused' refused record "$sku-4" "${day}T11:00:00Z" "$late" 2031-09-30 CHILL-A -80
check 'and the level is unchanged by the refused pick' test "$(quantity_of "$late" 2031-09-30 CHILL-A)" = 70
# A transaction is all or nothing. The marker of the refused pick must not
# exist, or its movement id could never be used again. An item that is not
# there comes back as an empty response.
marker_exists() {
  aws dynamodb get-item --table-name "$movements" --consistent-read --output json \
    --key "$(jq -cn --arg id "$1" '{pk: {S: ("MOVEMENT#" + $id)}, sk: {S: "MOVEMENT"}}')" | grep -q '"Item"'
}
check 'the refused pick left no trace in the ledger' refused marker_exists "$sku-4"
check 'while the accepted pick did' marker_exists "$sku-3"

# One racing pick. It runs in the background, in a process of its own, so
# it takes a directory of its own for the transaction file that record
# writes. It leaves a file behind if the pick was accepted.
race_one() {
  local attempt="$work/race-$1"
  mkdir -p "$attempt"
  if work="$attempt" record "$sku-race-$1" "${day}T12:00:${1}0Z" "$race" 2031-12-31 CHILL-C -10 >/dev/null 2>&1; then
    touch "$attempt/succeeded"
  fi
}

# INV-5 under concurrency: ten picks of 10 at the same moment, against a
# batch holding 50. Exactly five can succeed, whatever order they arrive in.
race="B-$sku-RACE"
record "$sku-race-0" "${day}T12:00:00Z" "$race" 2031-12-31 CHILL-C 50 >/dev/null
for n in 1 2 3 4 5 6 7 8 9 10; do
  race_one "$n" &
done
wait
check 'of ten simultaneous picks against stock for five, exactly five succeed' \
  test "$(find "$work" -name succeeded | wc -l)" -eq 5
check 'and the stock level ends at zero, not below' test "$(quantity_of "$race" 2031-12-31 CHILL-C)" = 0

# INV-3: first expired, first out. One query, already in expiry order.
fefo="$(aws dynamodb query --table-name "$levels" --output json \
  --key-condition-expression 'pk = :p AND begins_with(sk, :w)' \
  --expression-attribute-values "$(jq -cn --arg p "PRODUCT#$sku" --arg w "WH#$warehouse#EXP#" '{":p": {S: $p}, ":w": {S: $w}}')")"
check 'a product query returns batches in expiry order, earliest first' jq -e --arg e "$early" --arg l "$late" \
  --arg r "$race" '[.Items[].gsi2pk.S] == ["BATCH#" + $e, "BATCH#" + $l, "BATCH#" + $r]' <<<"$fefo"

# INV-4: the expiry sweep.
check 'the expiry index lists what expires on a given day' jq -e --arg e "$early" \
  '.Count == 1 and (.Items[0].sk.S | contains($e))' <<<"$(aws dynamodb query --table-name "$levels" \
    --index-name by-expiry-date --output json --key-condition-expression 'gsi1pk = :d AND begins_with(gsi1sk, :p)' \
    --expression-attribute-values "$(jq -cn --arg p "PRODUCT#$sku" '{":d": {S: "EXP#2031-06-15"}, ":p": {S: $p}}')")"

# INV-7: recall.
check 'the batch index finds every place a batch is held' jq -e \
  '.Count == 1 and .Items[0].gsi2sk.S == "WH#LOS1#ZONE#CHILL-A"' <<<"$(aws dynamodb query --table-name "$levels" \
    --index-name by-batch --output json --key-condition-expression 'gsi2pk = :b' \
    --expression-attribute-values "$(jq -cn --arg b "BATCH#$late" '{":b": {S: $b}}')")"
check 'the ledger lists every movement of a batch in time order' jq -e \
  '[.Items[].quantity.N] == ["100", "-30"]' <<<"$(aws dynamodb query --table-name "$movements" --output json \
    --key-condition-expression 'pk = :b AND begins_with(sk, :m)' \
    --expression-attribute-values "$(jq -cn --arg b "BATCH#$late" '{":b": {S: $b}, ":m": {S: "MOVE#"}}')")"

# Operations: what happened in a warehouse today.
check 'the warehouse index lists a day of movements in time order' jq -e --arg s "$sku" \
  '[.Items[] | select(.product.S == $s) | .quantity.N][0:4] == ["100", "40", "-30", "50"]' <<<"$(aws dynamodb query \
    --table-name "$movements" --index-name by-warehouse-day --output json --key-condition-expression 'gsi1pk = :w' \
    --expression-attribute-values "$(jq -cn --arg w "WH#$warehouse#DAY#$day" '{":w": {S: $w}}')")"

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
