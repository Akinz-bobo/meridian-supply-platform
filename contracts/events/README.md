# Event contracts

The shape of every event on the bus, as JSON Schema, with a validator and examples.

A contract is what a producer promises and what a consumer may rely on. Keeping it in the repository, with a check, means a producer cannot change an event's shape without the change being seen in review.

## What is here

| File                                           | What it is                                                                                                                                     |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| [`envelope.schema.json`](envelope.schema.json) | The detail of every event: `id`, `type`, `version`, `source`, `occurredAt`, `correlationId`, optional `causationId`, and `data`                |
| `<Type>.v<version>.schema.json`                | The schema of `data` for one event type at one version. Added by the service that publishes the event, in the pull request that adds the event |
| [`examples/valid/`](examples/valid/)           | Events that must pass                                                                                                                          |
| [`examples/invalid/`](examples/invalid/)       | Events that must fail, each breaking exactly one rule, named for the rule it breaks                                                            |

The fields of the envelope and the delivery rules are explained in [decision record 0006](../../docs/adr/0006-event-backbone-and-messaging-conventions.md). The list of events is the [event catalogue](../../docs/architecture/events.md).

## Checking an event

```bash
scripts/validate-event.py contracts/events/examples/valid/product-published.json
echo '{"type": "x"}' | scripts/validate-event.py --stdin
make contract-test
```

The validator checks the envelope. If the repository has a schema for the event's type and version, it also checks `data` against it. It prints each problem with the path of the value concerned:

```
INVALID contracts/events/examples/invalid/local-time.json
  $.occurredAt: '2031-03-04T10:30:00+01:00' does not match Z$
```

It has no dependencies. It implements the part of JSON Schema these contracts use, and **refuses a schema that uses anything else**, so a contract cannot contain a rule the validator quietly ignores.

## Adding an event

1. Add the event to the [event catalogue](../../docs/architecture/events.md).
2. Add `<Type>.v1.schema.json` describing `data`. Set `additionalProperties` to `false` and list what is `required`.
3. Add at least one example under `examples/valid/` and one under `examples/invalid/`.
4. `make contract-test`.

## Changing an event

- **Adding an optional field** is compatible. Change the schema in place.
- **Anything else is a new version**: removing or renaming a field, changing a type, making a field required. Add `<Type>.v2.schema.json` beside version 1 and publish both until every consumer has moved. Then remove version 1.

A consumer ignores fields it does not know and versions it does not handle.

## Where the contract is enforced

| Where           | What                                                                                                                       |
| --------------- | -------------------------------------------------------------------------------------------------------------------------- |
| This repository | `make contract-test`, in CI: every example behaves as its directory says, and every schema uses supported keywords only    |
| The producer    | Validates before publishing, and tests its events against the schema. Each service does this from milestone 6 on           |
| The bus         | A producer may publish only under its own source, enforced by IAM. The bus does not validate `data`                        |
| The consumer    | Ignores what it does not understand, and treats an event it cannot process as a failure that goes to its dead-letter queue |
