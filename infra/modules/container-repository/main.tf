# A private registry repository for one service's container images.
#
# A tag, once pushed, cannot be moved to another image. What runs in
# production is then exactly what was built, tested and scanned under that
# tag, and a deployment can always be traced to one build.

data "aws_region" "current" {}

locals {
  repository_arn = "arn:aws:ecr:${data.aws_region.current.region}:${var.account_id}:repository/${var.name}"
}

resource "aws_ecr_repository" "this" {
  name = var.name

  # No tag can be overwritten. A new build needs a new tag.
  image_tag_mutability = "IMMUTABLE"

  # Every image is scanned for known vulnerabilities when it is pushed.
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  # Refuse to delete a repository that still holds images, unless the
  # environment is disposable.
  force_delete = var.force_delete

  tags = var.tags
}

# Without this a repository grows for ever: every build of every branch
# stays, and is billed, until someone remembers to clean up.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove images that never got a tag, after ${var.untagged_retention_days} days."
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_retention_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the newest ${var.keep_tagged_images} tagged images, enough to roll back several releases."
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_tagged_images
        }
        action = { type = "expire" }
      },
    ]
  })
}

# What a role needs in order to pull. Attached to the execution role of a
# task or the role of a node.
data "aws_iam_policy_document" "pull" {
  statement {
    sid = "PullImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [local.repository_arn]
  }

  # Logging in to the registry is not tied to a repository.
  statement {
    sid       = "LogInToTheRegistry"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

# What the build needs in order to push. It can add images and cannot
# delete one or change the repository.
data "aws_iam_policy_document" "push" {
  source_policy_documents = [data.aws_iam_policy_document.pull.json]

  statement {
    sid = "PushImages"
    actions = [
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [local.repository_arn]
  }
}
