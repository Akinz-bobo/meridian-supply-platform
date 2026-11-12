# Plan-only tests. The provider is real with placeholder credentials so the
# rendered policies can be read. Nothing is called: no AWS account or
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
  name        = "meridian-prod-catalog"
  account_id  = "333333333333"
  kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
  tags = {
    Project = "meridian"
  }
}

run "a_tag_cannot_be_moved_to_another_image" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "Tags must be immutable. There is no input for it."
  }
}

run "scans_every_image_when_it_is_pushed" {
  command = plan

  assert {
    condition     = one(aws_ecr_repository.this.image_scanning_configuration).scan_on_push
    error_message = "Scanning on push must be on."
  }
}

run "encrypts_images_with_the_given_key" {
  command = plan

  assert {
    condition     = one(aws_ecr_repository.this.encryption_configuration).encryption_type == "KMS" && one(aws_ecr_repository.this.encryption_configuration).kms_key == "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
    error_message = "Images must be encrypted with the key that was passed."
  }
}

run "is_not_emptied_on_destroy_by_default" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.force_delete == false
    error_message = "force_delete must default to off."
  }
}

run "cleans_up_leftovers_and_keeps_enough_to_roll_back" {
  command = plan

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.tagStatus == "untagged" && jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.countNumber == 7
    error_message = "Untagged images are removed after 7 days by default."
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.countNumber == 30
    error_message = "The newest 30 images are kept by default."
  }
}

run "a_puller_can_pull_from_this_repository_and_nothing_else" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(output.pull_policy_json).Statement : statement
      if statement.Sid == "PullImages"
    ]).Resource == "arn:aws:ecr:eu-west-1:333333333333:repository/meridian-prod-catalog"
    error_message = "Pulling is limited to this repository."
  }

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.pull_policy_json).Statement : [
        for action in flatten([statement.Action]) : !can(regex("ecr:(Put|Upload|Initiate|Complete|Delete|BatchDelete|Set)", action)) && !strcontains(action, "*")
      ]
    ]))
    error_message = "The pull policy must not allow pushing, deleting or changing anything."
  }
}

run "a_pusher_can_add_images_and_not_remove_them" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.push_policy_json).Statement : [
        for action in flatten([statement.Action]) :
        !contains(["ecr:BatchDeleteImage", "ecr:DeleteRepository", "ecr:SetRepositoryPolicy", "ecr:PutLifecyclePolicy", "ecr:PutImageTagMutability"], action) && !strcontains(action, "*")
      ]
    ]))
    error_message = "The push policy must not allow deleting an image or changing the repository."
  }

  assert {
    condition = contains(flatten([
      for statement in jsondecode(output.push_policy_json).Statement : flatten([statement.Action])
    ]), "ecr:PutImage")
    error_message = "The push policy must allow pushing."
  }
}

run "only_the_registry_login_applies_to_every_resource" {
  command = plan

  assert {
    condition = alltrue([
      for statement in jsondecode(output.push_policy_json).Statement :
      statement.Resource != "*" || statement.Action == "ecr:GetAuthorizationToken"
    ])
    error_message = "Only ecr:GetAuthorizationToken, which has no resource, may use the wildcard resource."
  }
}

run "rejects_keeping_too_few_images_to_roll_back" {
  command = plan

  variables {
    keep_tagged_images = 1
  }

  expect_failures = [var.keep_tagged_images]
}

run "rejects_a_repository_without_a_customer_managed_key" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_a_name_with_upper_case_or_slashes" {
  command = plan

  variables {
    name = "Meridian/Catalog"
  }

  expect_failures = [var.name]
}
