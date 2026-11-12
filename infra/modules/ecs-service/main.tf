# One service on ECS Fargate, behind the load balancer.
#
# The module creates everything that belongs to the service and nothing
# that is shared: its task definition, its security group, its target
# group and listener rule, its log group and its scaling. The cluster, the
# load balancer and the roles are passed in.
#
# The container always runs as a non-root user, with a read-only root
# filesystem, no Linux capabilities and no way to gain privileges. Those
# are not inputs.

data "aws_region" "current" {}

locals {
  container_name = "app"

  # Listed in a fixed order, so that a change of one value is one line in
  # a plan and not a reshuffle of the whole definition.
  environment = [for name in sort(keys(var.environment)) : { name = name, value = var.environment[name] }]
  secrets     = [for name in sort(keys(var.secrets)) : { name = name, valueFrom = var.secrets[name] }]
}

resource "aws_cloudwatch_log_group" "this" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

# The service's own security group. Nothing is shared with other services:
# it accepts the load balancer on its port and nothing else.
resource "aws_security_group" "this" {
  name        = var.name
  description = "Tasks of ${var.name}. Reached only from the load balancer."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_load_balancer" {
  security_group_id            = aws_security_group.this.id
  description                  = "From the load balancer on port ${var.container_port}"
  referenced_security_group_id = var.load_balancer_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port

  tags = var.tags
}

# The other half of the same path: the load balancer may send to this
# service. Its security group has no egress to anything it was not told
# about.
resource "aws_vpc_security_group_egress_rule" "load_balancer_to_service" {
  security_group_id            = var.load_balancer_security_group_id
  description                  = "To ${var.name} on port ${var.container_port}"
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port

  tags = var.tags
}

# AWS APIs through the VPC endpoints or NAT, and partner APIs through NAT.
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to AWS services and partner APIs"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "dns" {
  for_each = toset(["udp", "tcp"])

  security_group_id = aws_security_group.this.id
  description       = "DNS to the VPC resolver over ${each.key}"
  cidr_ipv4         = var.vpc_cidr_block
  ip_protocol       = each.key
  from_port         = 53
  to_port           = 53

  tags = var.tags
}

# A data store the service uses: a rule pair between this service's group
# and the store's group, for one port. A service that names no store can
# reach none.
resource "aws_vpc_security_group_egress_rule" "to_data" {
  for_each = var.data_access

  security_group_id            = aws_security_group.this.id
  description                  = "To ${each.key} on port ${each.value.port}"
  referenced_security_group_id = each.value.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "data_from_service" {
  for_each = var.data_access

  security_group_id            = each.value.security_group_id
  description                  = "From ${var.name} to ${each.key} on port ${each.value.port}"
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port

  tags = var.tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory

  # Two roles, kept apart. The execution role is what ECS uses to start
  # the task: pull the image, write logs, fetch secrets. The task role is
  # what the application runs as.
  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    merge({
      name      = local.container_name
      image     = var.image
      essential = true

      # Hardening that no caller can turn off.
      user                   = var.container_user
      readonlyRootFilesystem = true
      privileged             = false
      linuxParameters = {
        capabilities       = { add = [], drop = ["ALL"] }
        initProcessEnabled = true
      }

      # With awsvpc networking the host port is the container port.
      portMappings = [
        { containerPort = var.container_port, hostPort = var.container_port, protocol = "tcp" },
      ]

      # Time to finish requests in flight after SIGTERM, before SIGKILL.
      stopTimeout = var.stop_timeout_seconds

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = local.container_name
        }
      }
      },
      # Values that are not secret. A secret never goes here: it would be
      # readable by anyone who can describe the task definition. Left out
      # when empty, because ECS does not return an empty list and the
      # definition would then look changed on every plan.
      length(local.environment) > 0 ? { environment = local.environment } : {},
      # References to Secrets Manager secrets or Parameter Store
      # parameters. ECS fetches the value when the task starts, with the
      # execution role. The task definition holds only the ARN.
      length(local.secrets) > 0 ? { secrets = local.secrets } : {},
    ),
  ])

  tags = var.tags
}

resource "aws_lb_target_group" "this" {
  name        = var.name
  vpc_id      = var.vpc_id
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"

  # How long the load balancer waits before removing a task that is being
  # stopped, so requests in flight can finish. Not longer than the task's
  # own stop timeout, or the task is gone before the wait ends.
  deregistration_delay = var.stop_timeout_seconds

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "this" {
  listener_arn = var.listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = var.path_patterns
    }
  }

  tags = var.tags
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  # A deployment that cannot become healthy is stopped and rolled back to
  # the last version that was, without anyone acting.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Never fewer healthy tasks than desired during a deployment: new tasks
  # start and pass health checks before old ones stop.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  # A shell in a running container. Off unless an incident needs it.
  enable_execute_command = var.enable_execute_command

  propagate_tags = "SERVICE"

  tags = var.tags

  lifecycle {
    # Autoscaling changes the count after creation. Without this, every
    # apply would set it back.
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener_rule.this]
}

resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.desired_count
  max_capacity       = var.max_count

  tags = var.tags
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value = var.cpu_target_percent

    # Add tasks quickly and remove them slowly, so a brief lull does not
    # leave the service short when the load returns.
    scale_out_cooldown = 60
    scale_in_cooldown  = 300

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
