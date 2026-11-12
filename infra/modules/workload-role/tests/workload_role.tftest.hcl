# Plan-only tests. The provider is real with placeholder credentials so the
# rendered trust policy can be read. Nothing is called: no AWS account or
# emulator is needed.

provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  name                     = "meridian-prod-catalog-task-role"
  description              = "Runs the catalog service on ECS."
  workload                 = "ecs-task"
  account_id               = "333333333333"
  permissions_boundary_arn = "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary"
  tags = {
    Project = "meridian"
  }
}

run "always_carries_the_permission_boundary" {
  command = plan

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary"
    error_message = "The role must carry the boundary it was given."
  }
}

run "an_ecs_task_role_is_assumed_by_ecs_tasks_of_this_account" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "ecs-tasks.amazonaws.com"
    error_message = "An ECS task role is assumed by ecs-tasks.amazonaws.com."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "333333333333"
    error_message = "The trust policy must be limited to tasks of this account."
  }
}

run "a_lambda_role_is_assumed_by_lambda" {
  command = plan

  variables {
    name     = "meridian-prod-scan-intake-role"
    workload = "lambda"
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com"
    error_message = "A Lambda role is assumed by lambda.amazonaws.com."
  }
}

run "a_pod_role_lets_eks_tag_the_session" {
  command = plan

  variables {
    name     = "meridian-prod-inventory-pod-role"
    workload = "eks-pod"
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "A pod role is assumed by the EKS Pod Identity service."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action) == toset(["sts:AssumeRole", "sts:TagSession"])
    error_message = "Pod Identity needs sts:TagSession as well as sts:AssumeRole."
  }
}

run "only_an_ec2_role_gets_an_instance_profile" {
  command = plan

  assert {
    condition     = length(aws_iam_instance_profile.this) == 0 && output.instance_profile_name == null
    error_message = "An ECS task role must not create an instance profile."
  }
}

run "an_ec2_role_gets_an_instance_profile" {
  command = plan

  variables {
    name     = "meridian-prod-erp-gateway-role"
    workload = "ec2"
  }

  assert {
    condition     = aws_iam_instance_profile.this[0].name == "meridian-prod-erp-gateway-role"
    error_message = "The instance profile shares the role's name."
  }
}

run "attaches_each_inline_policy_by_name" {
  command = plan

  variables {
    policies = {
      read-own-parameters = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"ssm:GetParameter\",\"Resource\":\"arn:aws:ssm:eu-west-1:333333333333:parameter/meridian/prod/catalog/*\"}]}"
    }
  }

  assert {
    condition     = aws_iam_role_policy.this["read-own-parameters"].name == "read-own-parameters"
    error_message = "An inline policy keeps the name it was given."
  }
}

run "rejects_an_unknown_compute_type" {
  command = plan

  variables {
    workload = "fargate"
  }

  expect_failures = [var.workload]
}

run "rejects_a_role_without_a_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = ""
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "rejects_administrator_access" {
  command = plan

  variables {
    managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  }

  expect_failures = [var.managed_policy_arns]
}

run "rejects_a_full_access_managed_policy" {
  command = plan

  variables {
    managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
  }

  expect_failures = [var.managed_policy_arns]
}

run "rejects_a_policy_name_with_spaces" {
  command = plan

  variables {
    policies = {
      "Read Parameters" = "{}"
    }
  }

  expect_failures = [var.policies]
}
