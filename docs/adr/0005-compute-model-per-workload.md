# 0005: Choose the compute model per workload by a stated rule

|        |            |
| ------ | ---------- |
| Status | Accepted   |
| Date   | 2026-11-11 |
| Issue  | #6         |

## Context

AWS offers several ways to run code. The platform has workloads of very different shapes: a bursty, stateless intake endpoint, long-running transactional services, nightly batch jobs, a multi-day human approval workflow, and a third-party file client that expects a persistent host.

Running everything on one model is simpler to operate, and it forces some workloads into a poor fit: a Kubernetes cluster kept up for a job that runs ten minutes a night, or a function stretched to hold database connection pools for a transactional service.

Using several models costs more in tooling and knowledge. If the choice per workload is not governed by a rule, it becomes taste, and the system becomes inconsistent.

## Decision

Each workload runs on the first model in this list that fits it:

| Order | If the workload is                                                                                                                                  | It runs on                       | Because                                                                                                                           |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 1     | A multi-step process with waits, retries or human steps                                                                                             | **Step Functions**               | State, retries and timeouts are declared, visible and cost nothing while waiting                                                  |
| 2     | Event-driven or bursty, stateless, and finishes in seconds                                                                                          | **Lambda**                       | Scales with the burst, costs nothing when idle                                                                                    |
| 3     | A scheduled or one-off batch job that runs for minutes                                                                                              | **ECS Fargate task**             | No time limit to design around, no servers, billed for the run                                                                    |
| 4     | A long-running service with steady, modest load and simple scaling needs                                                                            | **ECS Fargate service**          | A container behind a load balancer with the least to operate                                                                      |
| 5     | A long-running service that is high-volume, latency-sensitive, or needs fine control over rollout and scaling, or that ships as a group with others | **EKS**                          | Horizontal pod autoscaling on custom metrics, disruption budgets, progressive delivery, a common deployment model across services |
| 6     | Software that needs a persistent host, a fixed address or an agent that cannot be containerised                                                     | **EC2** in an Auto Scaling group | Nothing else fits. Kept to the minimum                                                                                            |

Applied to the planned workloads:

| Workload                                    | Model               | Rule |
| ------------------------------------------- | ------------------- | ---- |
| Curation workflow, planning orchestration   | Step Functions      | 1    |
| Scan intake, file validation, reporting API | Lambda              | 2    |
| Forecast and proposal jobs                  | ECS Fargate task    | 3    |
| Catalog service                             | ECS Fargate service | 4    |
| Inventory, procurement, budget              | EKS                 | 5    |
| ERP gateway                                 | EC2                 | 6    |

A workload that fits an earlier rule does not move to a later one for consistency's sake. Moving one in the other direction needs a new decision record.

## Consequences

- Each workload runs where it fits, and idle cost stays low: the intake path, the batch jobs and the workflows cost nothing when nothing is happening.
- The choice for a new workload is a lookup, and can be challenged against the rule in review.
- Four deployment paths to build and maintain: function packaging, ECS task definitions, Helm charts and an instance image. Milestone 5 and the pipeline work carry that cost.
- Observability has to be uniform across all of them: one log format, one correlation identifier and one tracing approach, whatever the runtime.
- Engineers need working knowledge of both ECS and Kubernetes. That is a real cost for a small team, accepted here because showing both in a realistic setting is one of the purposes of this repository. A team optimising only for operational simplicity could reasonably run rules 4 and 5 on a single platform.
- Lambda functions that need the database sit in the VPC and must manage connections carefully. None of the planned functions talk to RDS directly, by design.

## Alternatives considered

- **Everything on EKS.** One deployment model and one set of tools. It keeps a cluster busy for work that is idle most of the day, pushes workflow state into application code, and is a heavy host for a file client.
- **Everything serverless (Lambda and Step Functions).** Lowest idle cost. The transactional services would fight connection limits and cold starts, and the inventory service's sustained stream processing fits a long-running consumer better.
- **Everything on ECS.** A reasonable middle. It gives up Kubernetes-native autoscaling and rollout control for the busiest services, and still needs something else for workflows and bursts.
- **Choose per service by team preference.** No rule to review against, and it drifts.
