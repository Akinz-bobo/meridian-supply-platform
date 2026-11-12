# A message in a dead-letter queue

What to do when the alarm `<queue>-dlq-not-empty` fires.

- [What it means](#what-it-means)
- [First five minutes](#first-five-minutes)
- [Find out why](#find-out-why)
- [Fix, then redrive](#fix-then-redrive)
- [When not to redrive](#when-not-to-redrive)
- [Afterwards](#afterwards)
- [What has been tested](#what-has-been-tested)

## What it means

A consumer received the same message five times and did not acknowledge it. SQS moved it to the dead-letter queue, where it stays for 14 days.

It is one of two things:

| Cause                                                                                                                                                        | Typical sign                                                                               | Scope                                     |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ | ----------------------------------------- |
| **The consumer is broken.** A bad deployment, a dependency that is down, a missing permission                                                                | Many messages, of every kind, arriving in the dead-letter queue from the moment it started | Everything that consumer does has stopped |
| **The message is one the consumer cannot handle.** A producer sent something the contract does not allow, or the consumer has a bug that one message exposes | One or a few messages, all alike. The rest flow normally                                   | One business fact is not applied          |

Nothing has been lost. The message is intact, and every other consumer of the same event got its own copy and is unaffected.

## First five minutes

The queue name tells you the consumer and the event: `meridian-prod-budget-goods-received-dlq` is the budget service failing to process `GoodsReceived`.

```bash
queue=meridian-prod-budget-goods-received
dlq_url=$(aws sqs get-queue-url --queue-name "$queue-dlq" --query QueueUrl --output text)
queue_url=$(aws sqs get-queue-url --queue-name "$queue" --query QueueUrl --output text)

# How many, and is the main queue backing up as well?
aws sqs get-queue-attributes --queue-url "$dlq_url" --attribute-names ApproximateNumberOfMessages
aws sqs get-queue-attributes --queue-url "$queue_url" \
  --attribute-names ApproximateNumberOfMessages ApproximateAgeOfOldestMessage
```

- **The main queue is also growing:** the consumer is broken. Treat it as an outage of that service. Go to its dashboard and logs, and roll back if a deployment just happened.
- **The main queue is healthy:** it is the message. Continue below.

## Find out why

Look at a failed message without removing it. A visibility timeout of zero puts it straight back.

```bash
aws sqs receive-message --queue-url "$dlq_url" --max-number-of-messages 10 \
  --visibility-timeout 0 --attribute-names All
```

The body is the event envelope. Three things to do with it:

1. **Check it against the contract.**

   ```bash
   aws sqs receive-message --queue-url "$dlq_url" --visibility-timeout 0 \
     --query 'Messages[0].Body' --output text | scripts/validate-event.py --stdin
   ```

   If it is invalid, the producer is at fault. The `source` field says which service. Raise it with that team, and see [when not to redrive](#when-not-to-redrive).

2. **Find the consumer's error.** Search its logs for the event `id`, or the `correlationId`, which is on every log line that stems from the same original request.

3. **Find what was published.** The event log has every event for 30 days:

   ```
   fields @timestamp, source, `detail-type`, detail.id
   | filter detail.correlationId = "<correlationId>"
   | sort @timestamp asc
   ```

   run against the log group `/aws/events/meridian-prod-events`.

## Fix, then redrive

Redriving before the cause is fixed sends the same messages round the same loop and back into the dead-letter queue five receives later.

1. Fix the consumer and deploy it, or confirm the dependency is back.
2. Send the failed messages back to their queue:

   ```bash
   aws sqs start-message-move-task \
     --source-arn "arn:aws:sqs:<region>:<account>:$queue-dlq"
   ```

   With no destination, messages return to the queue they came from. Add `--max-number-of-messages-per-second` to feed a large backlog in gently.

3. Watch the dead-letter queue empty and stay empty, and the alarm return to OK.

Consumers are idempotent: each records the event `id` with its effect and ignores one it has already applied. So a redrive cannot apply anything twice, and redriving more than strictly needed is safe.

The operator role may start and cancel a move task on the environment's queues. It may not read message bodies in production, which may contain business data. Inspecting a body there needs an administrator, or the event log, which operators can read.

## When not to redrive

If the message itself is wrong, redriving it fails again. Decide, with the owner of the consuming service:

| Situation                                                | Action                                                                                                                                                    |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The producer published an event that breaks the contract | The producer fixes the cause and publishes a corrected event, with a new `id` and the same `correlationId`. The bad message is left to expire, or removed |
| The consumer should have tolerated it                    | Fix the consumer, then redrive                                                                                                                            |
| The fact no longer matters                               | Record the decision in the incident, and leave the message to expire                                                                                      |

A message is never edited in place and sent back. There would be no record of what was changed, and it would no longer be the event the producer published.

To remove one message, receive it with a normal visibility timeout and delete it by its receipt handle. Do not purge the queue unless every message in it has been accounted for.

## Afterwards

- If a producer sent an invalid event, its tests against the [contract](../../contracts/events/README.md) were missing or wrong. That is the fix that prevents the next one.
- If the consumer was broken by a deployment, the question for the review is why the deployment's own checks passed.
- Record how long the messages waited. That is how late the business fact was applied.

## What has been tested

`make event-check` does the mechanical part of this runbook on every pull request, in every environment: it makes a message fail five times, finds it in the dead-letter queue unchanged, sees the metric the alarm watches record it, redrives it, receives it from the original queue, and confirms the dead-letter queue is empty. It also confirms that an alarm changing state reaches the alarms topic.

Not tested: the alarm changing state by itself, because the emulator does not evaluate alarms. The check sets the state by hand to exercise the notification.
