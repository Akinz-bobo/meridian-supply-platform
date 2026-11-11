# Architecture overview

What Meridian is made of and how the parts work together. Read the [domain model](../domain/domain-model.md) first: the architecture follows from it.

> This describes the target design. The [milestones](https://github.com/Akinz-bobo/meridian-supply-platform/milestones) show how much of it exists today.

- [System context](#system-context)
- [Quality goals](#quality-goals)

## System context

Who and what the platform talks to.

```mermaid
flowchart TB
    supplier([Supplier])
    steward([Data steward])
    operator([Warehouse operator])
    buyer([Buyer and planner])
    finance([Finance controller])
    manager([Manager])

    subgraph meridian[Meridian Supply Platform]
        core[Catalog, inventory, procurement,<br/>budget, planning, analytics]
    end

    scanners[[Warehouse scanners]]
    erp[[Legacy finance system]]
    mail[[Email]]

    supplier -- "uploads product and price files" --> core
    steward -- "reviews and approves products" --> core
    operator --> scanners
    scanners -- "stock movement events" --> core
    buyer -- "purchase orders, proposals" --> core
    finance -- "budgets, approvals" --> core
    manager -- "dashboards" --> core
    core -- "invoices and payments, as files" --> erp
    erp -- "payment status, as files" --> core
    core -- "notifications" --> mail
```

| External party        | Direction | How                   | Why it matters to the design                                                    |
| --------------------- | --------- | --------------------- | ------------------------------------------------------------------------------- |
| Suppliers             | In        | File upload           | Files are large, slow and unreliable in format. Processing must be asynchronous |
| Warehouse scanners    | In        | HTTPS, in bursts      | Volume and burstiness make this a streaming problem                             |
| Legacy finance system | Both      | Files on a schedule   | It cannot call an API. It needs a host that exchanges files                     |
| Email                 | Out       | Managed email service | Approvals and alerts must reach people who are not in the application           |

## Quality goals

The properties the design is optimised for, in priority order. When two conflict, the higher one wins.

| #   | Goal                                     | What it means here                                                                      | How the design meets it                                                                                                           | How it is verified                             |
| --- | ---------------------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| 1   | **Correctness of stock and money**       | Stock is never negative or double counted. Budget is never overspent silently           | A ledger of movements as the source of truth, conditional writes, idempotent consumers, integer money                             | Invariant tests, reconciliation jobs           |
| 2   | **Availability of warehouse operations** | A warehouse can keep scanning when planning, analytics or the finance link is down      | Asynchronous events between services, three availability zones, no synchronous dependency from the scan path to anything optional | Failure injection tests                        |
| 3   | **Security**                             | Least privilege, encryption everywhere, a full audit trail                              | Private subnets, per-workload IAM roles, KMS, secrets management, audit logging, policy checks in CI                              | Policy as code, security scans, a threat model |
| 4   | **Operability**                          | A problem is visible, diagnosable and recoverable by someone who did not write the code | Structured logs, metrics, traces, alarms, runbooks, everything as code                                                            | Runbook drills                                 |
| 5   | **Cost awareness**                       | Pay for load, not for idle. Know what each part costs                                   | Serverless and scale-to-zero where load is bursty, budgets and tags, a cost model                                                 | Tag policy, cost estimates per environment     |
| 6   | **Changeability**                        | A new service or a new environment is routine                                           | Reusable modules, one event backbone, documented standards                                                                        | A new environment is one directory             |
