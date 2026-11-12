# Network and security baseline review

A review of everything milestone 2 built, against the [threat model](threat-model.md) and the [module standards](../module-standards.md), before data and compute are added on top of it.

|         |                                                                         |
| ------- | ----------------------------------------------------------------------- |
| Date    | 2026-11-12                                                              |
| Scope   | The nine modules and three layers of milestone 2                        |
| Issue   | [#22](https://github.com/Akinz-bobo/meridian-supply-platform/issues/22) |
| Outcome | 12 findings: 5 to fix now, 7 tracked for later milestones               |

- [Method](#method)
- [Findings](#findings)
- [Checklist by module](#checklist-by-module)
- [What the review could not check](#what-the-review-could-not-check)
- [Conclusion](#conclusion)

## Method

1. Write the threat model: assets, trust boundaries, actors, and each threat with the control that answers it.
2. For every threat, find the control in the code and the test or check that would fail if the control were removed. A control with no check counts as a gap.
3. Read each module against a fixed checklist (below).
4. Read the documentation against the code, looking for claims the code does not support.
5. Record each gap as a finding with a severity, and either fix it or track it.

Severity is judged by what an attacker or a mistake could do, assuming AWS enforces the configuration:

| Severity | Meaning                                                                                   |
| -------- | ----------------------------------------------------------------------------------------- |
| High     | Data could be lost or leave the account                                                   |
| Medium   | A protection is weaker than the standard says, or relies on every caller getting it right |
| Low      | Defence in depth, or a correctness problem with no direct exposure                        |

## Findings

| #   | Finding                                                                                                                                                                       | Severity | Decision                                                                                       | Issue                                                                   |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| F1  | The flow logs module leaves the encryption key optional, so it is not secure by default                                                                                       | Medium   | Fixed                                                                                          | [#55](https://github.com/Akinz-bobo/meridian-supply-platform/issues/55) |
| F2  | VPC endpoints have no policy. A compromised workload could copy data to another account's bucket or table through an endpoint                                                 | High     | Fixed                                                                                          | [#56](https://github.com/Akinz-bobo/meridian-supply-platform/issues/56) |
| F3  | Outbound traffic from workloads is limited by port and not by destination                                                                                                     | Medium   | Track. Needs a decision between an egress proxy, a network firewall and acceptance             | [#57](https://github.com/Akinz-bobo/meridian-supply-platform/issues/57) |
| F4  | The permission boundary allows `s3:DeleteObject*`, which includes deleting object versions, and `s3:PutObject*`, which includes object ACLs                                   | High     | Fixed                                                                                          | [#58](https://github.com/Akinz-bobo/meridian-supply-platform/issues/58) |
| F5  | The deploy role can schedule a key for deletion with a direct API call. The policy check only protects against plans                                                          | High     | Fixed                                                                                          | [#59](https://github.com/Akinz-bobo/meridian-supply-platform/issues/59) |
| F6  | All workloads share one security group that allows any port between members                                                                                                   | Medium   | Track. Belongs with the compute platforms, when services exist to separate                     | [#60](https://github.com/Akinz-bobo/meridian-supply-platform/issues/60) |
| F7  | API calls are not recorded. There is no audit trail yet                                                                                                                       | High     | Track. Already planned for milestone 11, now with an issue                                     | [#61](https://github.com/Akinz-bobo/meridian-supply-platform/issues/61) |
| F8  | Nothing alerts on a security finding: Access Analyzer results, rejected traffic, trust policy changes                                                                         | Medium   | Track                                                                                          | [#62](https://github.com/Akinz-bobo/meridian-supply-platform/issues/62) |
| F9  | The data route table is attached to the gateway endpoints, and the documentation calls this the data tier's path to S3. The data tier's network ACL makes that route unusable | Low      | Fixed. A design and its documentation contradicting each other is how wrong assumptions spread | [#63](https://github.com/Akinz-bobo/meridian-supply-platform/issues/63) |
| F10 | IMDSv2 is not enforced by an account default. The emulator does not support the setting                                                                                       | Medium   | Track. Enforce per instance when the EC2 and EKS modules are built                             | [#64](https://github.com/Akinz-bobo/meridian-supply-platform/issues/64) |
| F11 | The state bucket has no access logging                                                                                                                                        | Low      | Track. Needs the log archive bucket                                                            | [#65](https://github.com/Akinz-bobo/meridian-supply-platform/issues/65) |
| F12 | A pull request plan would use the deploy role on a real account. There is no read-only plan role                                                                              | Medium   | Track                                                                                          | [#66](https://github.com/Akinz-bobo/meridian-supply-platform/issues/66) |

### What the findings have in common

Three of the five fixes are places where something was true of **the environments** and not of **the module**. The environments passed a key to the flow logs module (F1). The policy check stopped a key deletion in a plan (F5). The route existed where the documentation said (F9). In each case the layer above compensated for a module or a role that did not protect itself. The module standards say a module must be safe with only its required inputs, and the review is where that was checked against every module at once.

The other two (F2, F4) are defaults that are wider than they look: an endpoint with no policy allows everything, and a trailing `*` on an action name admits actions nobody had in mind.

## Checklist by module

Each module was read against the same questions. A dash means the question does not apply.

| Module                 | Safe with only required inputs | No wildcard action on a wildcard resource                                                                           | Names and paths carry the environment | Every protection has a test | Documentation matches the code |
| ---------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | --------------------------- | ------------------------------ |
| `context`              | Yes                            | -                                                                                                                   | Yes                                   | Yes                         | Yes                            |
| `state-bucket`         | Yes                            | Yes                                                                                                                 | Yes                                   | Yes                         | Yes                            |
| `vpc`                  | Yes                            | -                                                                                                                   | Yes                                   | Yes                         | Yes                            |
| `vpc-endpoints`        | Yes, since F2                  | -                                                                                                                   | Yes                                   | Yes, since F2               | Yes, since F9                  |
| `vpc-flow-logs`        | Yes, since F1                  | Yes                                                                                                                 | Yes                                   | Yes                         | Yes                            |
| `tier-security-groups` | Yes, with F6 accepted for now  | -                                                                                                                   | Yes                                   | Yes                         | Yes                            |
| `kms-key`              | Yes                            | Yes. `kms:*` is granted to the account root in the key policy, which delegates to IAM and is the documented pattern | Yes                                   | Yes                         | Yes                            |
| `permission-boundary`  | Yes, since F4                  | Yes                                                                                                                 | Yes                                   | Yes, since F4               | Yes                            |
| `workload-role`        | Yes                            | Yes                                                                                                                 | Yes                                   | Yes                         | Yes                            |
| `access-roles`         | Yes, since F5                  | Recorded exception for the deploy policy                                                                            | Yes                                   | Yes                         | Yes                            |
| `account-baseline`     | Yes, with F10 open             | -                                                                                                                   | Yes                                   | Yes                         | Yes                            |
| `service-config`       | Yes                            | Yes                                                                                                                 | Yes                                   | Yes                         | Yes                            |

Also checked across all modules:

| Question                                                        | Result                                                                                                                                                |
| --------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Is any secret, key or credential in the repository or in state? | No. `make state-audit` and a search of the repository                                                                                                 |
| Does any module configure a provider or branch on the emulator? | No                                                                                                                                                    |
| Does any module look resources up by name or tag?               | No                                                                                                                                                    |
| Is every scanner and policy exception recorded with a reason?   | Yes. Two scanner exceptions and four policy exceptions, each with a statement                                                                         |
| Is every policy document readable at plan time?                 | Yes, after the fix described in the [access model](../access-model.md#policies-are-built-so-they-can-be-checked). `POL-IAM-5` now warns if one is not |

## What the review could not check

- **Enforcement.** The emulator stores security configuration and does not apply it. Nothing in this review was confirmed by a request being refused. The threat model lists this first among its residual risks.
- **The identity account and the GitHub environments.** Both are assumed to be configured as the threat model's assumptions say. Neither is in this repository.
- **Behaviour under load or failure.** Zone failure and NAT failure are handled by design and have not been exercised.

## Conclusion

The baseline is sound in structure: tiers, one-way paths between them, no long-lived credentials, a boundary on every workload role and a pipeline that cannot escalate. The review found five places where it was weaker than its own standard, two of them serious enough that data could have left the account or been destroyed. Those five are fixed in the pull requests that close issues 55, 56, 58, 59 and 63. Seven further findings depend on things that do not exist yet and are tracked in the milestones that build them.

All five fixes are merged, and each row above marked "Fixed" links to the issue that its pull request closed. Milestone 2 is complete.
