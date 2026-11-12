#!/usr/bin/env bash
# Sends events through an applied environment and follows them.
#
# Usage: event-check.sh <environment-directory>
#
# The messaging layer makes promises: an event put on the bus reaches every
# consumer interested in it and no other, a consumer receives the envelope
# as it was published, and a message that keeps failing is moved to the
# dead-letter queue and can be sent back, an alarm notifies the alarms
# topic, events for people reach the notifications topic, and the movement
# stream keeps the order of each warehouse. This script publishes events
# and records marked as its own, watches where they go, and removes what it
# can. Stream records cannot be removed: they expire with the retention.
#
# The jq programs in this file are single-quoted on purpose: $id and the
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

bus="meridian-$environment-events"
prefix="meridian-$environment"

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

queue_url() { aws sqs get-queue-url --queue-name "$1" --output json | jq -r '.QueueUrl'; }

depth() { # <queue url>: messages waiting, visible or not
  aws sqs get-queue-attributes --queue-url "$1" --output json \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible |
    jq -r '.Attributes | (.ApproximateNumberOfMessages | tonumber) + (.ApproximateNumberOfMessagesNotVisible | tonumber)'
}

# envelope <type> <source service> <event id>: an event that follows the
# contract, marked as coming from this check.
envelope() {
  jq -cn --arg type "$1" --arg source "meridian.$2" --arg id "$3" --arg run "$run" '{
    id: $id, type: $type, version: 1, source: $source,
    occurredAt: "2031-03-04T09:30:00Z",
    correlationId: "0193b2a4-6f00-7b11-8e2a-91c0d4e7a3b2",
    data: {check: $run}
  }'
}

# publish <type> <source service> <event id>
publish() {
  local detail
  detail="$(envelope "$1" "$2" "$3")"
  "$root/scripts/validate-event.py" --stdin <<<"$detail" >/dev/null
  aws events put-events --output json --entries "$(jq -cn --arg bus "$bus" --arg source "meridian.$2" \
    --arg type "$1" --arg detail "$detail" \
    '[{EventBusName: $bus, Source: $source, DetailType: $type, Detail: $detail}]')" |
    jq -e '.FailedEntryCount == 0' >/dev/null
}

# take <queue url> <event id>: receives until the event with that id
# arrives, deletes it, and prints its body. Fails if it does not arrive.
take() {
  local url=$1 id=$2 received body handle
  for _ in 1 2 3 4 5 6 7 8; do
    received="$(aws sqs receive-message --queue-url "$url" --wait-time-seconds 2 --max-number-of-messages 10 \
      --visibility-timeout 5 --output json || true)"
    [ -n "$received" ] || continue
    handle="$(jq -r --arg id "$id" '[.Messages[]? | select((.Body | fromjson | .id) == $id)][0].ReceiptHandle // empty' <<<"$received")"
    if [ -n "$handle" ]; then
      body="$(jq -r --arg id "$id" '[.Messages[]? | select((.Body | fromjson | .id) == $id)][0].Body' <<<"$received")"
      aws sqs delete-message --queue-url "$url" --receipt-handle "$handle"
      printf '%s\n' "$body"
      return 0
    fi
  done
  return 1
}

# absent <queue url> <event id>: true when no message with that id is there.
absent() {
  local received
  received="$(aws sqs receive-message --queue-url "$1" --wait-time-seconds 1 --max-number-of-messages 10 \
    --visibility-timeout 0 --output json || true)"
  [ -z "$received" ] || jq -e --arg id "$2" '[.Messages[]? | select((.Body | fromjson | .id) == $id)] | length == 0' <<<"$received" >/dev/null
}

# A uuid of this run's own, so events from an earlier run are never
# mistaken for this one's.
uuid() { printf '0193b2a4-%04x-7%03x-9%03x-%012x\n' $((RANDOM % 65536)) $((RANDOM % 4096)) $((RANDOM % 4096)) "$(date +%s%N | cut -c1-14)"; }
run="check-$(date +%s)-$$"

inventory_goods="$(queue_url "$prefix-inventory-goods-received")"
budget_goods="$(queue_url "$prefix-budget-goods-received")"
inventory_product="$(queue_url "$prefix-inventory-product-published")"
inventory_goods_dlq="$(queue_url "$prefix-inventory-goods-received-dlq")"

echo "Event check: $1 (bus $bus, run $run)"

# One event, two interested consumers, one that is not.
goods="$(uuid)"
check 'an event that follows the contract is accepted by the bus' publish GoodsReceived procurement "$goods"
body="$(take "$inventory_goods" "$goods" || true)"
check 'it reaches the inventory queue for that event' test -n "$body"
check 'the consumer receives the envelope exactly, without the wrapper the bus adds' jq -e --arg id "$goods" --arg run "$run" \
  '.id == $id and .type == "GoodsReceived" and .source == "meridian.procurement" and .data.check == $run
    and (has("detail") | not) and (has("detail-type") | not)' <<<"$body"
check 'the same event also reaches the budget queue' take "$budget_goods" "$goods"
check 'it does not reach a queue for another event' absent "$inventory_product" "$goods"

# A different event goes to its own consumer only.
product="$(uuid)"
check 'an event of another type is accepted' publish ProductPublished catalog "$product"
check 'it reaches the queue for that type' take "$inventory_product" "$product"
check 'and not the queues for the first type' absent "$inventory_goods" "$product"

# An event from outside the platform matches no rule.
outside="$(uuid)"
aws events put-events --output json --entries "$(jq -cn --arg bus "$bus" --arg detail "$(envelope GoodsReceived procurement "$outside")" \
  '[{EventBusName: $bus, Source: "someone.else", DetailType: "GoodsReceived", Detail: $detail}]')" >/dev/null
check 'an event whose source is not the platform reaches no consumer' absent "$inventory_goods" "$outside"

# Poison: a message the consumer can never process. It is received and
# not deleted, five times, which is what a crashing consumer does.
poison="$(uuid)"
publish GoodsReceived procurement "$poison"
take "$budget_goods" "$poison" >/dev/null || true
before="$(depth "$inventory_goods_dlq")"
for _ in 1 2 3 4 5 6 7 8; do
  aws sqs receive-message --queue-url "$inventory_goods" --wait-time-seconds 1 --visibility-timeout 0 \
    --max-number-of-messages 10 --output json >/dev/null || true
done
check 'a message received five times without being deleted leaves the queue' test "$(depth "$inventory_goods")" -eq 0
check 'and is in the dead-letter queue' test "$(depth "$inventory_goods_dlq")" -gt "$before"
dead="$(aws sqs receive-message --queue-url "$inventory_goods_dlq" --wait-time-seconds 2 --visibility-timeout 0 \
  --max-number-of-messages 10 --output json || true)"
check 'unchanged, so it can be inspected' jq -e --arg id "$poison" \
  'any(.Messages[]?; (.Body | fromjson | .id) == $id)' <<<"${dead:-{\}}"

# The alarm's input. The alarm on a dead-letter queue watches a metric, and
# while the message sits there the metric must show it. Metrics are sampled
# at intervals, so this waits for the next sample.
dead_letter_metric() {
  aws cloudwatch get-metric-statistics --namespace AWS/SQS --metric-name ApproximateNumberOfMessagesVisible \
    --dimensions "Name=QueueName,Value=$prefix-inventory-goods-received-dlq" --statistics Maximum --period 60 \
    --start-time "$(date -u -d '-5 minutes' +%FT%TZ)" --end-time "$(date -u -d '+1 minute' +%FT%TZ)" --output json |
    jq -e '[.Datapoints[]?.Maximum] | length > 0 and max >= 1' >/dev/null
}
seen=no
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if dead_letter_metric; then
    seen=yes
    break
  fi
  timeout 5 tail -f /dev/null || true
done
check 'the metric the dead-letter alarm watches shows the failed message' test "$seen" = yes

# Redrive: once the fault is fixed, the failed messages go back.
task="$(aws sqs start-message-move-task --output json \
  --source-arn "arn:aws:sqs:$region:$account:$prefix-inventory-goods-received-dlq" | jq -r '.TaskHandle // empty' || true)"
check 'the dead-letter queue can be redriven to its source queue' test -n "$task"
check 'the message is back in the queue, where a fixed consumer processes it' take "$inventory_goods" "$poison"
check 'and the dead-letter queue is empty again' test "$(depth "$inventory_goods_dlq")" -eq 0

# The alarm's output. When the alarm changes state it notifies the alarms
# topic. A temporary queue is subscribed to the topic to see what arrives,
# and the alarm is put into the alarm state by hand.
alarms_topic="arn:aws:sns:$region:$account:$prefix-alarms"
inbox="$prefix-event-check-$$"
inbox_url="$(aws sqs create-queue --queue-name "$inbox" --output json | jq -r '.QueueUrl')"
subscription="$(aws sns subscribe --topic-arn "$alarms_topic" --protocol sqs \
  --notification-endpoint "arn:aws:sqs:$region:$account:$inbox" --output json | jq -r '.SubscriptionArn')"
cleanup() {
  aws sns unsubscribe --subscription-arn "$subscription" >/dev/null 2>&1 || true
  aws sqs delete-queue --queue-url "$inbox_url" >/dev/null 2>&1 || true
  aws cloudwatch set-alarm-state --alarm-name "$prefix-inventory-goods-received-dlq-not-empty" \
    --state-value OK --state-reason 'Reset by the event check.' >/dev/null 2>&1 || true
}
trap cleanup EXIT

aws cloudwatch set-alarm-state --alarm-name "$prefix-inventory-goods-received-dlq-not-empty" \
  --state-value ALARM --state-reason 'Set by the event check.'
notice=''
for _ in 1 2 3 4 5; do
  notice="$(aws sqs receive-message --queue-url "$inbox_url" --wait-time-seconds 2 --output json || true)"
  [ -n "$notice" ] && break
done
check 'an alarm that changes state notifies the alarms topic' jq -e \
  'any(.Messages[]?; (.Body | fromjson | (.Message // .) | if type == "string" then fromjson else . end
    | .AlarmName) != null)' <<<"${notice:-{\}}"
check 'the notification names the alarm and its new state' jq -e --arg a "$prefix-inventory-goods-received-dlq-not-empty" \
  'any(.Messages[]?; (.Body | fromjson | (.Message // .) | if type == "string" then fromjson else . end)
    | .AlarmName == $a and .NewStateValue == "ALARM")' <<<"${notice:-{\}}"

# Events for people reach the notifications topic through a rule.
people="$prefix-event-check-people-$$"
people_url="$(aws sqs create-queue --queue-name "$people" --output json | jq -r '.QueueUrl')"
people_subscription="$(aws sns subscribe --topic-arn "arn:aws:sns:$region:$account:$prefix-notifications" --protocol sqs \
  --notification-endpoint "arn:aws:sqs:$region:$account:$people" --attributes RawMessageDelivery=true \
  --output json | jq -r '.SubscriptionArn')"
cleanup_people() {
  aws sns unsubscribe --subscription-arn "$people_subscription" >/dev/null 2>&1 || true
  aws sqs delete-queue --queue-url "$people_url" >/dev/null 2>&1 || true
  cleanup
}
trap cleanup_people EXIT

approval="$(uuid)"
publish ApprovalRequested budget "$approval"
check 'an event meant for people reaches the notifications topic' take "$people_url" "$approval"
ordinary="$(uuid)"
publish GoodsReceived procurement "$ordinary"
take "$inventory_goods" "$ordinary" >/dev/null || true
take "$budget_goods" "$ordinary" >/dev/null || true
check 'an ordinary event does not' absent "$people_url" "$ordinary"

# The movement stream: order within a partition key.
stream="$prefix-inventory-movement-stream"
for n in 1 2 3 4 5 6 7 8 9 10; do
  aws kinesis put-record --stream-name "$stream" --partition-key LOS1 --output json \
    --data "$(jq -cn --arg run "$run" --argjson n "$n" '{check: $run, warehouse: "LOS1", sequence: $n}' | base64 -w0)" >/dev/null
  aws kinesis put-record --stream-name "$stream" --partition-key ABV1 --output json \
    --data "$(jq -cn --arg run "$run" --argjson n "$n" '{check: $run, warehouse: "ABV1", sequence: $n}' | base64 -w0)" >/dev/null
done

# read_stream: every record of this run, in the order each shard returns
# them, as one JSON array.
read_stream() {
  local shard iterator page
  for shard in $(aws kinesis list-shards --stream-name "$stream" --output json | jq -r '.Shards[].ShardId'); do
    iterator="$(aws kinesis get-shard-iterator --stream-name "$stream" --shard-id "$shard" \
      --shard-iterator-type TRIM_HORIZON --output json | jq -r '.ShardIterator')"
    for _ in 1 2 3 4 5 6; do
      page="$(aws kinesis get-records --shard-iterator "$iterator" --limit 1000 --output json)"
      jq -c --arg run "$run" '.Records[] | .Data | @base64d | fromjson | select(.check == $run)' <<<"$page"
      iterator="$(jq -r '.NextShardIterator // empty' <<<"$page")"
      [ -n "$iterator" ] || break
      [ "$(jq '.Records | length' <<<"$page")" -gt 0 ] || break
    done
  done | jq -cs '.'
}
records="$(read_stream)"
check 'every record written to the stream can be read back' jq -e 'length == 20' <<<"$records"
for warehouse in LOS1 ABV1; do
  check "the movements of warehouse $warehouse are read in the order they were written" jq -e --arg w "$warehouse" \
    '[.[] | select(.warehouse == $w) | .sequence] == [range(1; 11)]' <<<"$records"
done
check 'a second reader gets the same records from the start' jq -e --argjson first "$records" '. == $first' <<<"$(read_stream)"

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
