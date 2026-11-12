# An ECS cluster for Fargate services.
#
# A cluster on Fargate has no servers to manage: it is a name that groups
# services, with settings for metrics and for what happens when someone
# opens a shell in a running container.

resource "aws_cloudwatch_log_group" "exec" {
  name              = var.exec_log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

resource "aws_ecs_cluster" "this" {
  name = var.name

  # Per-task and per-container metrics, without which a slow or leaking
  # container cannot be told from a healthy one.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  # A shell in a container is the most powerful access there is. Services
  # leave it off. When it is switched on for an incident, every command
  # typed and every line printed is recorded here, encrypted.
  configuration {
    execute_command_configuration {
      kms_key_id = var.logs_kms_key_arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.exec.name
      }
    }
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # On-demand capacity unless a service asks for spot. Spot tasks can be
  # stopped with two minutes' notice, which only some workloads tolerate.
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}
