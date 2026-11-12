# load-balancer

An application load balancer with a TLS listener that refuses everything no rule matches.

What a caller needs to know:

- **TLS only.** The one listener is HTTPS on 443, with a policy that accepts TLS 1.3 and 1.2. A policy that accepts older versions is refused at plan time. `redirect_http` adds a port 80 listener whose only action is a permanent redirect to 443.
- **Nothing is served by default.** A request that matches no listener rule gets a fixed 404 from the load balancer. A forgotten or mistyped route cannot fall through to a service.
- **Services attach themselves.** A service module creates its own target group and adds a rule to `https_listener_arn`. This module knows nothing about services.
- **Malformed requests stop here.** Invalid header fields are dropped, and desync mitigation is at its strictest, which refuses requests that a front end and a back end could parse differently.
- **Pass the public subnets and the load balancer security group** for an internet-facing load balancer. That group is the only one in the environment that accepts traffic from outside the VPC.
- **Deletion protection is on by default.**
- **Bring the certificate.** `certificate_arn` is an input, because issuing one involves the domain's DNS zone, which belongs to the caller.

Access logs are not configured yet: they need a log archive bucket, which is tracked with the other audit logging work.

See [compute](../../../docs/architecture/compute.md#the-way-in).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "compute"
}

module "load_balancer" {
  source = "../.."

  name = module.context.prefix
  tags = module.context.tags

  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1", "subnet-0123456789abcdef2"]
  security_group_ids = ["sg-0123456789abcdef0"]
  certificate_arn    = "arn:aws:acm:eu-west-1:333333333333:certificate/11111111-2222-3333-4444-555555555555"
}
```

## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.10.0, < 2.0.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| certificate\_arn | ARN of the certificate the TLS listener presents. | `string` | n/a | yes |
| name | Name of the load balancer. Build it from the context module's prefix. | `string` | n/a | yes |
| security\_group\_ids | Security groups of the load balancer. Pass the load balancer security group. | `list(string)` | n/a | yes |
| subnet\_ids | Subnets the load balancer is placed in, one per zone. Pass the public subnets for an internet-facing load balancer. | `list(string)` | n/a | yes |
| tags | Tags for every resource in the module. Take them from the context module. | `map(string)` | n/a | yes |
| deletion\_protection | Refuse to delete the load balancer. Turn off only in an environment that is disposable. | `bool` | `true` | no |
| idle\_timeout\_seconds | Seconds a connection may be idle before the load balancer closes it. Keep it below the keep-alive timeout of the services behind. | `number` | `60` | no |
| internal | Give the load balancer private addresses only, for traffic from inside the VPC or a connected network. | `bool` | `false` | no |
| redirect\_http | Also listen on port 80, only to redirect to 443. The load balancer security group must then allow port 80. | `bool` | `false` | no |
| tls\_policy | Security policy of the TLS listener. The default accepts TLS 1.3 and TLS 1.2 with forward secrecy only. | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the load balancer. |
| arn\_suffix | The part of the ARN that CloudWatch metrics use as the LoadBalancer dimension. |
| dns\_name | Host name of the load balancer. Point the environment's domain at it. |
| https\_listener\_arn | ARN of the TLS listener. A service adds its listener rule to it. |
| zone\_id | Hosted zone of the load balancer, for an alias record. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http_redirect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
<!-- END_TF_DOCS -->
