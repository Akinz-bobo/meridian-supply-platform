# Messaging review

A review of everything milestone 4 built, against the [threat model](threat-model.md#messaging) and the [module standards](../module-standards.md), before services publish and consume through it.

|         |                                                                                                 |
| ------- | ----------------------------------------------------------------------------------------------- |
| Date    | 2026-11-12                                                                                      |
| Scope   | The four modules and the `messaging` layer of milestone 4, the event contract and its validator |
| Issue   | [#102](https://github.com/Akinz-bobo/meridian-supply-platform/issues/102)                       |
| Outcome | 6 findings: 2 fixed now, 4 tracked. 4 further problems were found and fixed while building      |

- [Method](#method)
- [Findings](#findings)
- [Found and fixed while building](#found-and-fixed-while-building)
- [Checklist by module](#checklist-by-module)
- [What the review could not check](#what-the-review-could-not-check)
- [Conclusion](#conclusion)

## Method

The same as the earlier reviews, with one question added for this layer. Messaging exists so that nothing is lost between services, so for every path an event can take the review asked: **where can it be lost, and who would find out?**

| Path                                | Where it could be lost                          | Who finds out                                                 |
| ----------------------------------- | ----------------------------------------------- | ------------------------------------------------------------- |
| Producer to bus                     | The publish fails                               | The producer, which gets an error and retries from its outbox |
| Bus to queue                        | The bus cannot deliver                          | Was nobody. Finding E1                                        |
| Queue to consumer, consumer failing | The message is retried, then dead-lettered      | The dead-letter alarm                                         |
| Queue to consumer, consumer down    | The message waits, then expires after four days | Was nobody. Finding E2                                        |
| Alarm to a person                   | Nobody is subscribed                            | Nobody. Finding E3                                            |
| Stream to consumer                  | The consumer is down past retention             | Nobody yet. Finding E5                                        |

## Findings

Numbered E1 to E6. Threats in the threat model's messaging section are numbered M1 to M14.

| #   | Finding                                                                                                                                                                                               | Severity | Decision                                                                                                             | Issue                                                                     |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| E1  | An event the bus could not deliver to a queue was retried for a day and then discarded, with no record. A wrong queue policy or key policy would cause exactly that, for every event to that consumer | High     | Fixed. The target has a dead-letter queue and a one hour retry policy                                                | [#108](https://github.com/Akinz-bobo/meridian-supply-platform/issues/108) |
| E2  | Nothing alerted when a consumer was down. A consumer that receives nothing fails nothing, so nothing reached the dead-letter queue. Messages waited four days and were discarded                      | High     | Fixed. A second alarm per queue, on the age of the oldest message                                                    | [#109](https://github.com/Akinz-bobo/meridian-supply-platform/issues/109) |
| E3  | The alarms topic and the notifications topic have no subscribers. Every alarm is raised and reaches nobody                                                                                            | High     | Track. The plumbing is in place: `alarm_subscriptions` per environment. The destinations are an operational decision | [#110](https://github.com/Akinz-bobo/meridian-supply-platform/issues/110) |
| E4  | The contract covers the envelope. The `data` of each event has no schema until its producer is built                                                                                                  | Medium   | Track. Enforced from the first service                                                                               | [#111](https://github.com/Akinz-bobo/meridian-supply-platform/issues/111) |
| E5  | Nothing alerts when the stream's consumer falls behind, and a stream has no dead-letter queue                                                                                                         | Medium   | Track. With the inventory service                                                                                    | [#112](https://github.com/Akinz-bobo/meridian-supply-platform/issues/112) |
| E6  | The notifications topic delivers the JSON envelope. A person subscribed by email would receive a JSON document                                                                                        | Low      | Track. A formatter, when the first events for people exist                                                           | [#113](https://github.com/Akinz-bobo/meridian-supply-platform/issues/113) |

E1 and E2 are the same mistake made twice: an alarm on the failure that was easy to picture, a message the consumer rejects, and none on the two quieter ones, an event that never arrives and a consumer that is not there. Both were found by walking each path in the table above and not by any test.

## Found and fixed while building

| What                                                                                                                                                                                   | How it was found                                                                                                 | Fix                                                                                                                  | Pull request |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------ |
| CloudWatch was not in the messaging key's policy. An alarm publishing to the encrypted topic would have been refused at encryption, and the alarm would have notified nobody, silently | Reading what each publishing service needs. The emulator evaluates no key policy, so no test could have shown it | CloudWatch added to the key policy. The topic module's README says a publishing service must be named in both places | #105         |
| The layer could not be torn down: the emulator can create a CloudWatch Logs resource policy and cannot delete one                                                                      | The teardown rehearsal                                                                                           | The policy is an input of the bus module, turned off by the layer where the target is the emulator                   | #103         |
| A redrive policy that referred to a queue's ARN from the resource was unknown at plan time, so a test could not read it                                                                | The module's own tests                                                                                           | ARNs built from names, with explicit dependencies                                                                    | #104         |
| The event check read the alarm's metric after the message had been redriven                                                                                                            | The check failing once                                                                                           | It polls while the message is still in the dead-letter queue                                                         | #107         |

## Checklist by module

| Module                 | Safe with only required inputs | Encrypted with the messaging key, and no way to turn it off | Policies name one resource and are known at plan time | Refuses plain transport                           | Every protection has a test | Exercised in the pipeline                                                                                   |
| ---------------------- | ------------------------------ | ----------------------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `event-bus`            | Yes                            | Yes                                                         | Yes                                                   | Not applicable. EventBridge has no plain endpoint | Yes                         | Publishing, in the event check. Archive counted by hand. Event log not, the emulator does not deliver to it |
| `event-consumer-queue` | Yes, since E1 and E2           | Yes                                                         | Yes                                                   | Yes, both queues                                  | Yes                         | Yes. Fan-out, dead-letter, redrive                                                                          |
| `notification-topic`   | Yes                            | Yes                                                         | Yes                                                   | Yes                                               | Yes                         | Yes. An alarm notification and an event for people                                                          |
| `event-stream`         | Yes                            | Yes                                                         | Yes                                                   | Not applicable. Kinesis has no plain endpoint     | Yes                         | Yes. Order per partition key, two readers                                                                   |

Across the layer:

| Question                                        | Result                                                                                                                  |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Can a producer publish as another service?      | Not by its policy. Not proven by a refused request                                                                      |
| Can an event be lost without anyone being told? | Not between the bus and a queue consumer, since E1 and E2. Yes at the last step, to a person: E3. Yes on the stream: E5 |
| Does the layer read another layer's state?      | No. Three facts from Parameter Store                                                                                    |
| Is every alarm wired to the alarms topic?       | Yes. The smoke test checks all six                                                                                      |
| Can the layer be destroyed and re-created?      | Yes. In the pipeline's teardown, and by hand                                                                            |
| Is the contract enforced anywhere?              | In CI for the examples, and in the event check, which validates what it publishes. Not on the bus                       |

## What the review could not check

- **IAM, resource policies and key policies.** The whole access design of this layer is in policies the emulator stores and does not evaluate.
- **Alarm evaluation.** The emulator never changes an alarm's state.
- **Delivery to the event log**, and **replay from the archive**.
- **Throughput and order across shards.** One shard, a handful of records.

## Conclusion

Events flow, fail and recover as designed, and that is checked on every pull request. The layer's weakest point is its last step: every failure now raises an alarm, and no alarm reaches a person. That is finding E3 and it is the first thing to settle before this carries real traffic.
