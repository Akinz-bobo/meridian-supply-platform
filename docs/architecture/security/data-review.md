# Data layer review

A review of everything milestone 3 built, against the [threat model](threat-model.md#data) and the [module standards](../module-standards.md), before services are built on the stores.

|         |                                                                                               |
| ------- | --------------------------------------------------------------------------------------------- |
| Date    | 2026-11-12                                                                                    |
| Scope   | The five modules and the `data` layer of milestone 3, and the pipeline changes made with them |
| Issue   | [#78](https://github.com/Akinz-bobo/meridian-supply-platform/issues/78)                       |
| Outcome | 7 findings: 2 fixed now, 5 tracked. 6 further problems were found and fixed while building    |

- [Method](#method)
- [Findings](#findings)
- [Found and fixed while building](#found-and-fixed-while-building)
- [Checklist by module](#checklist-by-module)
- [What the review could not check](#what-the-review-could-not-check)
- [Conclusion](#conclusion)

## Method

The same as the [baseline review](baseline-review.md#method): extend the threat model, find for each threat the control and the check that would fail without it, read each module against a fixed checklist, and read the documentation against the code.

One step was added for this layer: **use each store**. A store can be configured correctly and still not do its job, so each one was exercised through its API the way a service would use it. Those exercises are now `make data-check` and run in the pipeline.

## Findings

Numbered D1 to D7. Threats in the threat model's data section are numbered S1 to S14.

| #   | Finding                                                                                                                                                                                                                               | Severity | Decision                                         | Issue                                                                   |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------ | ----------------------------------------------------------------------- |
| D1  | The table write policy lists `dynamodb:TransactWriteItems`, which is not an IAM action. A transaction is authorised by the item actions inside it. IAM accepts unknown actions silently, so the statement was harmless and misleading | Low      | Fixed                                            | [#88](https://github.com/Akinz-bobo/meridian-supply-platform/issues/88) |
| D2  | The movement ledger is append-only in the design. The only write policy on offer also allowed updating and deleting items, so the service that writes the audit record could rewrite it                                               | Medium   | Fixed. A new `append_policy_json`                | [#89](https://github.com/Akinz-bobo/meridian-supply-platform/issues/89) |
| D3  | Supplier uploads are untrusted files and nothing inspects them                                                                                                                                                                        | Medium   | Track. Belongs with the workflow that reads them | [#90](https://github.com/Akinz-bobo/meridian-supply-platform/issues/90) |
| D4  | The database has a master user and no application role, so nothing but an administrator can connect safely yet                                                                                                                        | Medium   | Track. Created with the first service            | [#91](https://github.com/Akinz-bobo/meridian-supply-platform/issues/91) |
| D5  | Stores have no alarms: storage, connections, throttling, evictions, failed backups                                                                                                                                                    | Medium   | Track                                            | [#92](https://github.com/Akinz-bobo/meridian-supply-platform/issues/92) |
| D6  | No restore has returned real data, and no recovery time is measured. The emulator creates the restored store empty                                                                                                                    | High     | Track. Needs a real account                      | [#93](https://github.com/Akinz-bobo/meridian-supply-platform/issues/93) |
| D7  | The verification scripts assume the emulator's way of selecting an account, and some write test data. Against real accounts they need credentials handling and a decision about production                                            | Medium   | Track                                            | [#94](https://github.com/Akinz-bobo/meridian-supply-platform/issues/94) |

The scanner also reports, at low severity, that the uploads bucket has no access logging. That is the same finding as F11 of the baseline review and is carried on [#65](https://github.com/Akinz-bobo/meridian-supply-platform/issues/65).

## Found and fixed while building

These did not wait for the review. Each was found by running something, and each is described in the pull request where it was fixed.

| What                                                                                                                                                         | How it was found                                                                                                               | Fix                                                                                                                | Pull request |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ | ------------ |
| The security scanner evaluated every environment layer with its variables unknown, because it does not follow the symbolic link to the shared variables file | It reported the production database as unprotected, which was false. Replacing the link with a copy made the finding disappear | `make scan` scans a copy with links resolved. A deliberately inverted setting is now caught                        | #85          |
| The teardown rehearsal could not destroy staging and production                                                                                              | The pipeline: `DeleteTable` refused, because the tables are protected                                                          | `make teardown`: lift protections deliberately, then destroy. The procedure for decommissioning a real environment | #81          |
| `make teardown` then stopped lifting protections                                                                                                             | The pipeline again, after `disposable = false` was written into the variable files. A file outranks an environment variable    | The override is a command line variable                                                                            | #85          |
| The backup tag also landed on the database's log group                                                                                                       | Listing every resource that carried the tag after the first apply                                                              | `store_tags`, which reach the store only. The backup check asserts both sides                                      | #87          |
| A passwordless `default` cache user, which Valkey user groups refuse                                                                                         | The first apply failed on it, on the emulator as it would on AWS                                                               | No default user. Simpler and correct                                                                               | #86          |
| The rehearsal grew from 7 minutes to 16 as stores were added                                                                                                 | Run history                                                                                                                    | One job per environment, in parallel. About 7 minutes again                                                        | #84          |

Two of these are about the checks themselves and not about the infrastructure: a scanner that could not see variables, and a rehearsal that could not tear down what it built. A check that cannot fail is worse than no check, because it is trusted.

## Checklist by module

| Module              | Safe with only required inputs | Encrypted with a customer managed key, and no way to turn it off | No credential in configuration or state         | Access policies name one store and are known at plan time                 | Every protection has a test | Used through its API in the pipeline                                       |
| ------------------- | ------------------------------ | ---------------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------- | --------------------------- | -------------------------------------------------------------------------- |
| `data-bucket`       | Yes                            | Yes                                                              | -                                               | Yes                                                                       | Yes                         | Uploaded, overwritten and deleted by hand. Configuration in the smoke test |
| `dynamodb-table`    | Yes                            | Yes                                                              | -                                               | Yes, since D1 and D2                                                      | Yes                         | Yes. 18 checks of the key design                                           |
| `postgres-database` | Yes                            | Yes                                                              | Yes. The master password is managed by RDS      | No policy output. Access is by IAM database authentication, tracked in D4 | Yes                         | Yes. 11 checks, connecting with the managed credentials                    |
| `redis-cache`       | Yes                            | Yes                                                              | Yes. No auth token. Users authenticate with IAM | Yes                                                                       | Yes                         | The access rule, against a separate Valkey server. 15 checks               |
| `backup-plan`       | Yes                            | Yes                                                              | -                                               | -                                                                         | Yes                         | Yes. 8 checks, including a backup job                                      |

Also checked across the layer:

| Question                                                    | Result                                                                  |
| ----------------------------------------------------------- | ----------------------------------------------------------------------- |
| Does the `data` layer read any other layer's state?         | No. Seven facts from Parameter Store                                    |
| Is any secret in the remote state of either layer?          | No. `make state-audit`                                                  |
| Does every store carry a classification?                    | Yes. `POL-TAG-4`                                                        |
| Can any store be deleted by an ordinary apply outside dev?  | No. Deletion protection, and `POL-PROTECT-1` and `POL-DB-5` on the plan |
| Is every emulator difference that affects a claim recorded? | Yes. Differences 11 to 22                                               |

## What the review could not check

- **Enforcement**, as before. Bucket policies, key policies, cache users and TLS are configuration the emulator stores and does not apply.
- **Recovery.** Finding D6.
- **Behaviour at volume.** The key design was exercised with a handful of items and ten concurrent writers. Throughput, hot partitions and index lag are not modelled.
- **Managed service behaviour**: failover, rotation of the master secret, scheduled backups, lifecycle transitions.

## Conclusion

The data layer has one property worth stating plainly: there is no database password, cache password or other stored credential anywhere in it, and that is checked on every apply.

The two findings fixed here were both about a policy saying more than it should. The five tracked depend on services, alarms or a real account. The most serious, D6, is that recovery has not been demonstrated. Until it has, the recovery targets in the data architecture are intentions.
