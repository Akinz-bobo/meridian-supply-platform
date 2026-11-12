# Sample service

The smallest thing worth deploying. It exists to prove the compute platforms: it is deployed to ECS and to EKS through the pipeline, sits behind the load balancer, and is replaced by real services from milestone 6 on, which are deployed the same way.

| Path        | Answers                                                                                                                                                           |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/healthz`  | `{"status": "ok"}`. For load balancer and platform health checks                                                                                                  |
| `/`         | The service, environment, platform and version it was told it is                                                                                                  |
| `/identity` | How it would obtain AWS credentials, and for which role: `ecs-task-role`, `eks-pod-identity`, `environment-variables` or `none`. Never a key, a secret or a token |

Behind the load balancer every path is also served under `/sample/`.

## What it demonstrates

| Property                                 | How                                                                                                                     |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Runs as a non-root user                  | `USER 10001:10001` in the Dockerfile, numeric so Kubernetes can verify it                                               |
| Read-only root filesystem                | It writes nothing. Bytecode caching is off                                                                              |
| No capabilities, no privilege escalation | Needs none, so the platforms drop them all                                                                              |
| Stops cleanly                            | Handles `SIGTERM`: stops accepting, finishes requests in flight, exits. A deployment never cuts a request off           |
| Logs as the platform expects             | One JSON object per line on standard output. Health checks are not logged                                               |
| Configured from outside                  | Service name, environment, platform and version come from environment variables set by the task definition or the chart |
| Reproducible                             | The base image is pinned by digest                                                                                      |
| Nothing to patch but the interpreter     | Standard library only                                                                                                   |

## Run it

```bash
make service-test                 # unit tests, no Docker needed
make image ENV=dev SERVICE=sample # build and push to the environment's repository

docker build -t sample services/sample
docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges -p 8080:8080 sample
curl localhost:8080/identity
```
