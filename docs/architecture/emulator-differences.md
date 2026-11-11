# Emulator differences

Where the emulator behaves differently from AWS, as found while building this platform. Each entry says what differs, how it was found and what we do about it.

The rule from [decision record 0002](../adr/0002-develop-against-an-aws-emulator.md) is that a difference is recorded here and handled through configuration, never hidden with emulator-specific logic inside a module.

Emulator version these were observed on: Floci 2.4.0.

| #   | Area                | Difference                                                                                                                                                                              | Found                                                                                                | Handling                                                                                                           |
| --- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| 1   | EC2 images          | An image lookup with only `owners = ["amazon"]` and `most_recent = true` can return a Windows image, which the emulator refuses to launch because it runs instances as Linux containers | Initial spike                                                                                        | Always filter images by name. This is correct practice on AWS too, where an unfiltered lookup is non-deterministic |
| 2   | RDS endpoints       | The endpoint of a database instance is an address on the local Docker bridge network with a mapped port, not a DNS name on port 5432                                                    | Initial spike                                                                                        | Never assume the port. Always read `address` and `port` from the resource, which is also correct on AWS            |
| 3   | API Gateway URLs    | An HTTP API is invoked at `http://localhost:4566/execute-api/<api-id>/<stage>/<path>`, not at `https://<api-id>.execute-api.<region>.amazonaws.com`                                     | Initial spike                                                                                        | The invoke URL is computed in one output per environment, switched by the same variable that selects the emulator  |
| 4   | Credentials and IAM | Any non-empty credentials are accepted, and IAM policies are not fully enforced. A call that AWS would deny may succeed                                                                 | Documented by the emulator                                                                           | IAM correctness is checked statically, by policy checks on the plan, and is listed as not proven by the emulator   |
| 5   | Container image     | The emulator image contains neither `curl` nor `wget`                                                                                                                                   | While adding a health check in [#9](https://github.com/Akinz-bobo/meridian-supply-platform/issues/9) | Use the health check that ships with the image                                                                     |

## What the emulator cannot tell us

Whatever passes against the emulator, these remain unverified until the platform is applied to a real account:

- performance, latency and throughput
- real service quotas and limits
- full IAM enforcement
- cost
- behaviour across regions and across real account boundaries
- managed service behaviour that depends on AWS's own control plane, such as failover timing, rotation schedules and upgrade windows

## Reporting a new difference

Open a bug with the resource, the Terraform that reproduces it and the emulator version. If a workaround is needed, it goes in configuration with a link back to the row added here.
