# Module standards

What every Terraform module in this repository looks like, and why. There will be more than twenty modules. If each has the same shape, a reader who has understood one can find their way around all of them.

- [What a module is](#what-a-module-is)
- [Layout](#layout)
- [Rules](#rules)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [Secure by default](#secure-by-default)
- [Tests](#tests)
- [Documentation](#documentation)
- [Creating a module](#creating-a-module)
- [Checklist](#checklist)

## What a module is

A module packages **one building block with one reason to change**: a queue with its dead-letter queue, a database with its subnet group and parameter group, a bucket with its protections.

```mermaid
flowchart LR
    subgraph layer[State layer: environments/prod/messaging]
        call[main.tf<br/>values only]
    end
    subgraph modules[infra/modules]
        ctx[context<br/>names and tags]
        mod[sqs-consumer-queue<br/>queue, dead-letter queue,<br/>alarm, policy]
    end
    call -- "environment, component" --> ctx
    ctx -- "prefix, tags" --> call
    call -- "name, tags, settings" --> mod
    mod -- "arn, url" --> call
    call -- publishes --> ps[(Parameter Store)]
```

The split between the two is strict:

|                                | Modules             | State layers                    |
| ------------------------------ | ------------------- | ------------------------------- |
| Contain                        | Resources and logic | Calls to modules, with values   |
| Know about                     | One building block  | One environment                 |
| Configure a provider           | Never               | Always, through the shared file |
| Mention an environment by name | Never               | Through `var.environment` only  |
| Have state                     | No                  | Yes                             |

A module is the wrong tool for a single resource with no opinions added. Wrapping `aws_sns_topic` in a module that passes every argument through adds a layer and removes nothing.

## Layout

```
infra/modules/<name>/
  main.tf            resources
  variables.tf       inputs
  outputs.tf         outputs
  versions.tf        Terraform and provider version constraints
  README.md          description by hand, the rest generated
  examples/basic/    the smallest working call, shown in the README
  tests/             terraform test files
```

Larger modules may split `main.tf` by concern (`iam.tf`, `alarms.tf`). They may not add nested modules: if part of a module is reusable, it is a module of its own.

Names are kebab case and say what is built, not which AWS service is used when the two differ: `state-bucket`, not `s3`.

## Rules

1. **No provider configuration.** A module declares which providers it needs in `versions.tf` and nothing more. The caller decides the region, the account and the endpoint.
2. **No emulator awareness.** No variable, condition or branch that depends on whether the target is the emulator ([decision record 0002](../adr/0002-develop-against-an-aws-emulator.md)).
3. **Names and tags come in from outside.** A module takes `name` and `tags` as inputs, and the caller gets them from the [`context`](../../infra/modules/context/README.md) module. A module never builds a name from an environment string itself.
4. **Version constraints are minimums.** `>= 6.0`, not `~> 6.0`. The state layer pins exact versions with its lock file. A module that pins tightly forces every caller to upgrade in step.
5. **No data sources that look things up by name or tag.** A module is given identifiers. Lookups make a plan depend on what happens to exist in the account.
6. **One comment style.** `#` comments. The linter enforces it.

## Inputs

- Every variable has a `description` and a `type`. The linter fails without them, and the README is generated from them.
- **Required means no sensible default exists.** `name`, `tags`, a VPC identifier. Everything else has a default that is safe for production.
- **Validate what can be validated.** A `validation` block turns a confusing API error at apply into a clear message at plan:

  ```hcl
  variable "noncurrent_version_retention_days" {
    description = "How long a replaced state version is kept before it is deleted."
    type        = number
    default     = 90

    validation {
      condition     = var.noncurrent_version_retention_days >= 30
      error_message = "Keep old state versions for at least 30 days, so a bad apply found late can still be rolled back."
    }
  }
  ```

  The error message says what is allowed and why.

- **Prefer specific types to `any`.** An object type documents the shape and catches a typo in a key.
- **Environment differences are variables.** Whether a database is multi-AZ is an input with a production-safe default, set lower in `dev`'s values. It is never `var.environment == "prod" ? ... : ...` inside a module.
- **No secrets as inputs** where it can be avoided. A module that needs a password generates it and stores it in Secrets Manager, and outputs the secret's ARN.

## Outputs

- Every output has a `description`.
- Output what a caller needs to **use** the resource: identifiers, ARNs, names, endpoints, and the ARN of any role or policy a consumer must attach.
- Do not output whole resources. It couples callers to every attribute.
- An output that carries a secret is marked `sensitive = true`. Better, output a reference to where the secret is stored.

## Secure by default

A caller who passes only the required inputs gets a resource that is safe for production. Making it less safe takes an explicit input, visible in review.

| Concern                | Default                                                                       |
| ---------------------- | ----------------------------------------------------------------------------- |
| Encryption at rest     | On, with a customer managed key                                               |
| Public access          | Blocked                                                                       |
| Transport              | TLS required where the service allows a policy                                |
| Deletion               | Protected. `force_destroy`, `skip_final_snapshot` and the like default to off |
| Logging                | On                                                                            |
| Backups and versioning | On                                                                            |

Some protections are not inputs at all. The state bucket cannot be made public by any caller. If a protection should never be removed, do not offer the switch.

## Tests

Every module has tests in `tests/`, run with `terraform test`.

| Kind                            | Provider                               | Needs        | Proves                                                                   |
| ------------------------------- | -------------------------------------- | ------------ | ------------------------------------------------------------------------ |
| Plan tests with `mock_provider` | Mocked                                 | Nothing      | The module's logic: defaults, validations, what it promises to configure |
| Apply tests                     | Real provider, pointed at the emulator | The emulator | Resources are created in a workable order and can be destroyed           |

Plan tests are the baseline. They run in a second or two with no network, so they run on every commit. What to assert:

- **Every protection the module promises.** If the README says the bucket is versioned, a test fails when versioning is removed.
- **Every validation**, with `expect_failures`.
- **Every input that changes behaviour**, set to a non-default value.

Test names are sentences describing behaviour: `refuses_to_be_destroyed_with_state_in_it_by_default`, not `test_force_destroy`.

Apply tests are added where ordering or integration is the risk, which mostly means modules with several interdependent resources. They live in `tests-emulator/`, use an account of their own so they cannot touch an environment, and run with `make test-emulator` and in the pipeline. Plan tests stay in `tests/` so that `make test` never needs the emulator.

The whole environment being applied, smoke tested and destroyed in the [pipeline](../guides/pipeline.md) is the integration test for how modules fit together.

## Documentation

A module's `README.md` has two parts.

```markdown
# state-bucket

Written by hand: what the module creates, what is always on,
what a caller cannot turn off, and links to the decision records.

<!-- BEGIN_TF_DOCS -->

Generated: usage example, requirements, inputs, outputs, resources.
<!-- END_TF_DOCS -->
```

| Part                                     | Source                                      | Updated by  |
| ---------------------------------------- | ------------------------------------------- | ----------- |
| Title and description                    | Written by hand, above the marker           | The author  |
| Usage                                    | `examples/basic/main.tf`, included verbatim | `make docs` |
| Requirements, inputs, outputs, resources | The module's code                           | `make docs` |

Because the usage section is the real example file, and the example is validated on every change, the example in the documentation cannot be wrong.

`make docs` regenerates every README. `make docs-check` fails if one is out of date, or if a description is still the placeholder. CI runs the check, so a pull request that changes an input without regenerating the README does not merge.

The generated section is not formatted by the Markdown formatter, since it is not written by a person and the two tools would fight over table layout.

## Creating a module

```bash
make module NAME=sqs-consumer-queue
```

This creates the layout above with a `name` and `tags` input, an empty test file with the mocked provider set up, a basic example and a README with the markers. Then:

1. Add resources to `main.tf`.
2. Add inputs with descriptions, types, safe defaults and validations.
3. Add outputs with descriptions.
4. Write the tests.
5. Replace the placeholder description in `README.md`.
6. `make docs`, then `make check`.

## Checklist

For the author and the reviewer of a new or changed module.

- [ ] One building block, one reason to change
- [ ] No provider block, no environment names, no emulator conditions
- [ ] `name` and `tags` come from the caller
- [ ] Every variable and output has a description, and variables have types
- [ ] Defaults are safe for production
- [ ] Inputs that can be wrong have validations with helpful messages
- [ ] Protections that must never be removed are not inputs
- [ ] Tests cover every promise, every validation and every behaviour-changing input
- [ ] `examples/basic` is the smallest working call
- [ ] The README description says what is on by default and why
- [ ] `make check` passes
- [ ] If the module publishes parameters, their names are documented as part of its interface
