# Messaging

How services tell each other what happened: the bus, the contract every event follows, and who is allowed to say what. The reasoning is in [decision record 0006](../adr/0006-event-backbone-and-messaging-conventions.md), and the list of events is the [event catalogue](events.md).

It covers the bus, the contract, consumer queues, notification topics and the movement stream.

- [The shape of it](#the-shape-of-it)
- [The bus](#the-bus)
- [The contract](#the-contract)
- [Who may publish what](#who-may-publish-what)
- [Consumer queues](#consumer-queues)
- [Topics](#topics)
- [The movement stream](#the-movement-stream)
- [The messaging layer](#the-messaging-layer)
- [Checking the flow](#checking-the-flow)
- [How it is enforced](#how-it-is-enforced)
- [What the emulator does not prove](#what-the-emulator-does-not-prove)

## The shape of it

```mermaid
flowchart LR
    producer[A producer<br/>its own role] -- "PutEvents, as its own source" --> bus{{Event bus<br/>meridian-env-events}}
    bus --> archive[(Archive<br/>90 days, for replay)]
    bus --> log[(Event log<br/>30 days, for questions)]
    bus -- "one rule per consumer and event" --> queues[Consumer queues]
```

A producer puts an event on the bus and knows nothing about who receives it. A consumer never reads the bus: it has a queue of its own, fed by a rule. Adding a consumer changes nothing for the producer.

## The bus

One bus per environment, `meridian-<env>-events`, built by the [`event-bus` module](../../infra/modules/event-bus/README.md).

| Part             | Purpose                                                                                                   |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| Bus              | Receives events and matches them against rules                                                            |
| Bus policy       | Denies publishing to anything outside the account                                                         |
| Archive          | Keeps every event for 90 days, so a new consumer, or one that lost data, can have the past replayed to it |
| Event log        | A readable copy of every event for 30 days. "Was it published, and what did it say" is a query            |
| Publish policies | One per producer, limited to that producer's source                                                       |

The archive and the log overlap on purpose. The archive can be replayed and cannot be read. The log can be read and cannot be replayed.

## The contract

Every event has the same envelope, defined as JSON Schema in [`contracts/events`](../../contracts/events/README.md):

```json
{
  "id": "0193b2a4-7c1e-7d3a-9f0b-2a6c1e4d5f60",
  "type": "ProductPublished",
  "version": 1,
  "source": "meridian.catalog",
  "occurredAt": "2031-03-04T09:30:00Z",
  "correlationId": "0193b2a4-6f00-7b11-8e2a-91c0d4e7a3b2",
  "causationId": "0193b2a4-6f9d-7c40-a1d3-5b8e2f0c9a71",
  "data": { "sku": "SKU-1042" }
}
```

| Rule in the schema                           | Why                                                                            |
| -------------------------------------------- | ------------------------------------------------------------------------------ |
| `type` is PascalCase with at least two words | An event is a fact in the past tense: `ProductPublished`, not `publishProduct` |
| `source` is `meridian.<service>`             | It is what the publish policy checks                                           |
| `occurredAt` is UTC, with a time and a `Z`   | A local time read in another zone is a wrong time                              |
| `version` is an integer from 1               | It selects the schema for `data`                                               |
| No field outside the envelope                | Business data goes under `data`, where its own schema applies                  |

`scripts/validate-event.py` checks an event against the envelope, and `data` against the schema for its type and version when the repository has one. It is tested in CI with events that must pass and events that must fail.

## Who may publish what

Two controls, at different levels.

| Control                                                                         | Stops                                                                  |
| ------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Each producer's IAM policy allows `events:PutEvents` only with its own `source` | A service publishing an event that claims to come from another service |
| The bus policy denies principals outside the account                            | Anyone adding the bus to another account's reach                       |

What neither stops: a service publishing a well-formed event with wrong content under its own name. A consumer trusts the producer for the facts. That is why the producer is identified and cannot be impersonated.

## Consumer queues

A consumer never reads the bus. It has a queue for each event it is interested in, built by the [`event-consumer-queue` module](../../infra/modules/event-consumer-queue/README.md), which has the diagram.

| The queue gives the consumer | How                                                                                                                    |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Buffering                    | Events wait in the queue while the consumer is slow, deploying or down. Four days by default                           |
| Retries                      | A message that is received and not deleted becomes visible again and is delivered again                                |
| Isolation                    | Each consumer has its own queue. One consumer's backlog or poison message does not touch another                       |
| A place for failures         | After five failed receives a message moves to the dead-letter queue, raises an alarm and waits 14 days to be looked at |

The first three queues:

| Queue                                        | Consumer  | Event              | For                                                                         |
| -------------------------------------------- | --------- | ------------------ | --------------------------------------------------------------------------- |
| `meridian-<env>-inventory-product-published` | Inventory | `ProductPublished` | Knowing a product's storage class and shelf life before stock of it arrives |
| `meridian-<env>-inventory-goods-received`    | Inventory | `GoodsReceived`    | Recording the receipt as a movement                                         |
| `meridian-<env>-budget-goods-received`       | Budget    | `GoodsReceived`    | Turning a commitment into actual spend                                      |

Two of them take the same event. That is the point of the design: procurement publishes `GoodsReceived` once and does not know that two services act on it.

A queue is added to `messaging/consumers.tf` when its consumer is about to be built. Each queue's URL is published under the consumer's own path, `/meridian/<env>/<service>/queues/<event>-url`.

**What a consumer must do.** Delivery is at least once, so a consumer records each event `id` with its effect and ignores one it has seen. It deletes a message only after its effect is committed. It lets a message it cannot process fail, so that the message reaches the dead-letter queue, and does not swallow the error.

## Topics

Two per environment, built by the [`notification-topic` module](../../infra/modules/notification-topic/README.md).

```mermaid
flowchart LR
    alarms[CloudWatch alarms<br/>dead-letter queues, and later every alarm] --> at[(Alarms topic)]
    bus{{Event bus}} -- "rule: events for people" --> nt[(Notifications topic)]
    at --> oncall[On-call: chat, pager, email]
    nt --> people[Buyers, controllers, warehouse leads]
```

| Topic                          | Receives                                                                                                                                                                                         | From              |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------- |
| `meridian-<env>-alarms`        | Every alarm state change, to alarm and back to OK                                                                                                                                                | CloudWatch        |
| `meridian-<env>-notifications` | The events that exist to tell a person something: `ApprovalRequested`, `BatchExpired`, `BatchRecalled`, `BatchShortDated`, `BudgetExceeded`, `ReplenishmentProposed`, `StockDiscrepancyDetected` | A rule on the bus |

**Why notifications go through a topic and not a queue.** A queue has one consumer that must process every message. A topic fans out to whoever is subscribed and does not care whether anyone is. An approval request should reach a controller's inbox and the team's chat, and adding a third destination should not involve the budget service.

**Subscriptions are not in this repository.** Who is on call, and which chat channel, differ by environment and change without a deployment. The module takes them as an input, and an environment adds them in its own values. An environment with no subscriptions still has working topics: the messages go nowhere.

**The key policy.** CloudWatch and EventBridge publish as services, so both are named in the topic policy and, in the foundation layer, in the messaging key's policy. Without the second, a message is refused at encryption and the alarm silently notifies nobody. The baseline review of this milestone checks for exactly that.

## The movement stream

Warehouse scans do not go over the bus. They go through a Kinesis stream, `meridian-<env>-inventory-movement-stream`, built by the [`event-stream` module](../../infra/modules/event-stream/README.md).

```mermaid
flowchart LR
    scanners[Handheld scanners] --> api[Scan intake API]
    api -- "PutRecord, key = warehouse" --> stream[[Movement stream<br/>72 hours]]
    stream -- "in order per warehouse" --> inventory[Inventory<br/>applies each movement to the ledger]
    stream --> lake[Analytics<br/>lands every movement in the data lake]
```

| Question                          | Bus and queue                                      | Stream                                                              |
| --------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------- |
| Order                             | None promised                                      | In order per partition key                                          |
| Volume                            | Business events, at the pace of business decisions | Hundreds of thousands of scans a day, in bursts at shift start      |
| Several readers of the same data  | A queue each, fed separately                       | Each reads the same records at its own position                     |
| Reading again                     | Replay from the archive, to a rule                 | Any reader, any time within retention                               |
| A record that cannot be processed | Moves to a dead-letter queue                       | Blocks its shard until handled. The consumer must decide what to do |

**The partition key is the warehouse.** The order that matters is the order of movements within one warehouse: a receipt must be applied before the pick that takes from it. Movements in different warehouses are independent, so they may be processed in parallel.

A coarser key, one for everything, would put all traffic on one shard. A finer one, such as the batch, would spread load better and lose the order between a batch and the zone it moves through. If one warehouse ever outgrows a shard, the key becomes warehouse and zone, which keeps the order that matters and is a decision to make with real traffic in front of us.

**The last row of the table is the cost of a stream.** There is no dead-letter queue. A consumer that fails on a record and retries for ever stops everything behind it in that shard. The inventory service therefore applies each movement in the idempotent transaction described in the [inventory data model](inventory-data-model.md#recording-a-movement), and a movement it cannot apply, such as one that would make stock negative, is recorded as a `StockDiscrepancyDetected` event and skipped. It is never retried for ever.

**Retention is 72 hours**, so that the inventory service can be down over a weekend and still read every movement when it returns.

## The messaging layer

`infra/environments/<env>/messaging`, applied after `data` and destroyed before it. It reads the messaging key, the logs key and the workload boundary from Parameter Store, and publishes the bus under `/meridian/<env>/events/`.

| Parameter             | Used by                                     |
| --------------------- | ------------------------------------------- |
| `bus-name`, `bus-arn` | Producers, and the rules of consumer queues |
| `archive-arn`         | Starting a replay                           |
| `log-group-name`      | Queries during an incident                  |

## Checking the flow

`make event-check ENV=<env>` runs [`scripts/event-check.sh`](../../scripts/event-check.sh) against an applied environment. It publishes events and stream records marked as its own and follows them.

| Check                                                                                                           | What it shows                                                  |
| --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| An event that follows the contract is accepted, and reaches both queues interested in it                        | Fan-out: one publish, two independent consumers                |
| It does not reach a queue for another event type, and an event from outside the platform reaches no consumer    | Rules match what they should and nothing else                  |
| The body received is the envelope exactly                                                                       | The consumer gets what the producer sent                       |
| A message received five times without being deleted leaves the queue and is in the dead-letter queue, unchanged | Failures are kept, not dropped or retried for ever             |
| The metric the alarm watches shows it                                                                           | The alarm has something to fire on                             |
| A redrive returns it to the queue, and the dead-letter queue is empty                                           | The [runbook](../runbooks/dead-letter-queue.md) works          |
| An alarm that changes state notifies the alarms topic, naming the alarm and the state                           | Someone would be told                                          |
| An event meant for people reaches the notifications topic, and an ordinary one does not                         | The notification rule                                          |
| Twenty records in two warehouses are read back in order per warehouse, and a second reader gets the same        | The stream keeps order per partition key and can be read again |

It runs in the pipeline after every apply, in every environment. Before publishing, each test event is passed through the contract validator, so the check also fails if the envelope and the examples drift apart.

## How it is enforced

| Rule                                                         | Where                                                                                        |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| A producer publishes only under its own source               | Module tests on the rendered publish policies                                                |
| Nothing outside the account publishes                        | Module test, and the smoke test reading the bus policy back                                  |
| Events follow the envelope                                   | `make contract-test`, in CI                                                                  |
| A contract cannot contain a rule the validator ignores       | The validator refuses unsupported keywords, and a test checks every schema in the repository |
| The bus, archive, log rule and log group exist as configured | `make smoke`                                                                                 |

## What the emulator does not prove

- **Delivery to the event log.** The emulator stores a rule that targets a log group and delivers nothing to it. Difference 23.
- **IAM and resource policies.** A producer publishing under another's source, a rule other than a queue's own delivering to it, a consumer writing to a stream: none is refused here. They are tested on the rendered policies.
- **Encryption.** Keys are accepted. The bus does not return its key (difference 24), and no key policy is evaluated, which is why the missing CloudWatch entry in the messaging key's policy could only be found by reading.
- **Alarm evaluation.** The metric is recorded and the notification is delivered when the state is set by hand. The emulator never changes the state itself. Difference 27.
- **Order across shards, and behaviour under load.** An on-demand stream has one shard here.

What it does do is listed as difference 28: rules deliver with the detail extracted, queues dead-letter and redrive, topics deliver, and the stream keeps order per key.
