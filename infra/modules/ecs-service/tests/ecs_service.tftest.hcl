# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }
}

variables {
  name                            = "meridian-prod-catalog"
  cluster_arn                     = "arn:aws:ecs:eu-west-1:333333333333:cluster/meridian-prod-compute"
  cluster_name                    = "meridian-prod-compute"
  vpc_id                          = "vpc-0123456789abcdef0"
  vpc_cidr_block                  = "10.30.0.0/16"
  subnet_ids                      = ["subnet-private-a", "subnet-private-b", "subnet-private-c"]
  image                           = "333333333333.dkr.ecr.eu-west-1.amazonaws.com/meridian-prod-catalog:589969013abb"
  execution_role_arn              = "arn:aws:iam::333333333333:role/meridian-prod-catalog-execution-role"
  task_role_arn                   = "arn:aws:iam::333333333333:role/meridian-prod-catalog-task-role"
  listener_arn                    = "arn:aws:elasticloadbalancing:eu-west-1:333333333333:listener/app/meridian-prod-compute/abc/def"
  listener_rule_priority          = 100
  path_patterns                   = ["/catalog", "/catalog/*"]
  health_check_path               = "/catalog/healthz"
  load_balancer_security_group_id = "sg-lb"
  log_group_name                  = "/meridian/prod/catalog/ecs"
  logs_kms_key_arn                = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
  tags = {
    Project = "meridian"
  }
}

run "the_container_cannot_run_as_root_or_write_to_its_filesystem" {
  command = plan

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].user == "10001:10001"
    error_message = "The container runs as a numeric, non-root user."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].readonlyRootFilesystem == true
    error_message = "The root filesystem must be read-only. There is no input for it."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].privileged == false
    error_message = "The container must not be privileged."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].linuxParameters.capabilities.drop == ["ALL"]
    error_message = "Every Linux capability must be dropped."
  }
}

run "runs_on_fargate_with_separate_roles" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.this.requires_compatibilities == toset(["FARGATE"]) && aws_ecs_task_definition.this.network_mode == "awsvpc"
    error_message = "The task runs on Fargate, with a network interface of its own."
  }

  assert {
    condition     = aws_ecs_task_definition.this.execution_role_arn != aws_ecs_task_definition.this.task_role_arn
    error_message = "The role that starts the task and the role the application runs as must be different."
  }
}

run "has_no_public_address_and_its_own_security_group" {
  command = plan

  assert {
    condition     = one(aws_ecs_service.this.network_configuration).assign_public_ip == false
    error_message = "Tasks must not have public addresses."
  }

  assert {
    condition     = aws_security_group.this.name == "meridian-prod-catalog"
    error_message = "The service has a security group named after it."
  }
}

run "accepts_only_the_load_balancer_on_its_port" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_load_balancer.referenced_security_group_id == "sg-lb" && aws_vpc_security_group_ingress_rule.from_load_balancer.from_port == 8080 && aws_vpc_security_group_ingress_rule.from_load_balancer.to_port == 8080
    error_message = "The only ingress is from the load balancer's group, on the container port."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_load_balancer.cidr_ipv4 == null
    error_message = "Ingress is by group reference, never by address range."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.load_balancer_to_service.security_group_id == "sg-lb"
    error_message = "The load balancer's group gets the matching egress rule."
  }
}

run "reaches_no_data_store_unless_told" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.to_data) == 0 && length(aws_vpc_security_group_ingress_rule.data_from_service) == 0
    error_message = "With no data_access, no rule to a data store exists."
  }
}

run "gets_a_rule_pair_for_each_data_store_it_names" {
  command = plan

  variables {
    data_access = {
      postgresql = { security_group_id = "sg-data", port = 5432 }
    }
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.to_data["postgresql"].referenced_security_group_id == "sg-data" && aws_vpc_security_group_egress_rule.to_data["postgresql"].from_port == 5432
    error_message = "The service's group may send to the store's group on the store's port."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.data_from_service["postgresql"].security_group_id == "sg-data"
    error_message = "The store's group gets the matching ingress rule."
  }
}

run "rolls_back_a_deployment_that_does_not_become_healthy" {
  command = plan

  assert {
    condition     = one(aws_ecs_service.this.deployment_circuit_breaker).enable && one(aws_ecs_service.this.deployment_circuit_breaker).rollback
    error_message = "The deployment circuit breaker must be on, with rollback."
  }

  assert {
    condition     = aws_ecs_service.this.deployment_minimum_healthy_percent == 100
    error_message = "A deployment must never run fewer healthy tasks than desired."
  }
}

run "does_not_allow_a_shell_by_default" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.enable_execute_command == false
    error_message = "Execute command is off unless asked for."
  }
}

run "passes_secrets_by_reference" {
  command = plan

  variables {
    environment = { LOG_LEVEL = "info" }
    secrets     = { PARTNER_TOKEN = "arn:aws:secretsmanager:eu-west-1:333333333333:secret:/meridian/prod/catalog/secrets/partner-api-token-AbCdEf" }
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets == [{ name = "PARTNER_TOKEN", valueFrom = "arn:aws:secretsmanager:eu-west-1:333333333333:secret:/meridian/prod/catalog/secrets/partner-api-token-AbCdEf" }]
    error_message = "A secret appears in the task definition as a reference, never as a value."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment == [{ name = "LOG_LEVEL", value = "info" }]
    error_message = "Plain configuration is passed as environment variables."
  }
}

run "routes_its_own_paths_and_checks_health_on_its_own_path" {
  command = plan

  assert {
    condition     = one(one(aws_lb_listener_rule.this.condition).path_pattern).values == toset(["/catalog", "/catalog/*"])
    error_message = "The listener rule matches the service's path patterns."
  }

  assert {
    condition     = one(aws_lb_target_group.this.health_check).path == "/catalog/healthz" && aws_lb_target_group.this.target_type == "ip"
    error_message = "The target group checks the given health path and targets task addresses."
  }
}

run "drains_for_as_long_as_the_container_is_given_to_stop" {
  command = plan

  assert {
    condition     = tonumber(aws_lb_target_group.this.deregistration_delay) == jsondecode(aws_ecs_task_definition.this.container_definitions)[0].stopTimeout
    error_message = "The load balancer must stop sending before the container is killed, and wait no longer than that."
  }
}

run "scales_between_the_desired_count_and_a_ceiling" {
  command = plan

  assert {
    condition     = aws_appautoscaling_target.this.min_capacity == 2 && aws_appautoscaling_target.this.max_capacity == 6
    error_message = "Autoscaling keeps between two and six tasks by default."
  }

  assert {
    condition     = one(aws_appautoscaling_policy.cpu.target_tracking_scaling_policy_configuration).target_value == 60
    error_message = "Autoscaling aims for 60 percent CPU by default."
  }
}

run "logs_to_an_encrypted_group_with_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 90 && aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
    error_message = "The service's log group needs retention and the logs key."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-group"] == "/meridian/prod/catalog/ecs"
    error_message = "The container logs to the service's log group."
  }
}

run "rejects_the_latest_tag" {
  command = plan

  variables {
    image = "333333333333.dkr.ecr.eu-west-1.amazonaws.com/meridian-prod-catalog:latest"
  }

  expect_failures = [var.image]
}

run "rejects_an_image_with_no_tag" {
  command = plan

  variables {
    image = "333333333333.dkr.ecr.eu-west-1.amazonaws.com/meridian-prod-catalog"
  }

  expect_failures = [var.image]
}

run "rejects_running_as_root" {
  command = plan

  variables {
    container_user = "0"
  }

  expect_failures = [var.container_user]
}

run "rejects_a_secret_passed_as_plain_configuration" {
  command = plan

  variables {
    environment = { DATABASE_PASSWORD = "hunter2" }
  }

  expect_failures = [var.environment]
}

run "rejects_a_secret_given_as_a_value" {
  command = plan

  variables {
    secrets = { PARTNER_TOKEN = "s3cr3t" }
  }

  expect_failures = [var.secrets]
}

run "rejects_a_rule_that_would_take_every_request" {
  command = plan

  variables {
    path_patterns = ["/*"]
  }

  expect_failures = [var.path_patterns]
}

run "rejects_a_ceiling_below_the_desired_count" {
  command = plan

  variables {
    desired_count = 4
    max_count     = 2
  }

  expect_failures = [var.max_count]
}

run "rejects_a_privileged_port" {
  command = plan

  variables {
    container_port = 80
  }

  expect_failures = [var.container_port]
}
