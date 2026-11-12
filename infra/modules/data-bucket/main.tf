# A private, encrypted, versioned bucket for the platform's data.
#
# What is always true, whatever the caller passes: no public access, no
# ACLs, versioning on, encryption with a customer managed key, and no
# request accepted without TLS. What the caller decides: how long objects
# and old versions are kept, and when they move to cheaper storage.

locals {
  # Built from the name and not read from the bucket, so that the policies
  # below are known at plan time and can be policy checked.
  bucket_arn = "arn:aws:s3:::${var.name}"

  tags = merge(var.tags, { DataClassification = var.data_classification })
}

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    # Disables ACLs entirely. Access is governed by policies alone, and
    # every object belongs to the bucket owner whoever uploaded it.
    object_ownership = "BucketOwnerEnforced"
  }
}

# Overwriting or deleting an object keeps the previous version. A workload
# cannot remove versions: the permission boundary denies it.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    # A bucket key lets S3 reuse one data key for many objects, which cuts
    # the number of KMS calls, and their cost, by up to 99 percent.
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Versioning must be on before a rule about old versions means anything.
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "retention"
    status = "Enabled"

    filter {}

    dynamic "transition" {
      for_each = var.transitions

      content {
        days          = transition.value.days
        storage_class = transition.value.storage_class
      }
    }

    dynamic "expiration" {
      for_each = var.expiration_days == null ? [] : [var.expiration_days]

      content {
        days = expiration.value
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    # An upload that was started and never finished is invisible in a
    # listing and is billed until it is removed.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # When the current version of an object is deleted or expires it leaves a
  # delete marker. Once every old version behind it is gone the marker has
  # nothing left to hide, and this removes it.
  rule {
    id     = "remove-orphaned-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }
}

resource "aws_s3_bucket_notification" "this" {
  count = var.eventbridge_notifications ? 1 : 0

  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # An upload that names an encryption method must name KMS. One that
  # names none gets the bucket default, which is this bucket's key.
  statement {
    sid       = "DenyUploadsNotEncryptedWithKms"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  # An upload that names a key must name this bucket's key. Otherwise an
  # object could be stored under a key its readers cannot use, or one an
  # attacker controls.
  statement {
    sid       = "DenyUploadsWithAnotherKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [var.kms_key_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  # The public access block must exist first, or the policy call can be
  # rejected while the bucket is still being configured.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Policies for the roles that use the bucket. A service attaches one of
# these to its workload role instead of writing its own.

data "aws_iam_policy_document" "read" {
  statement {
    sid       = "ListTheBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.bucket_arn]
  }

  statement {
    sid       = "ReadObjects"
    actions   = ["s3:GetObject", "s3:GetObjectTagging", "s3:GetObjectVersion"]
    resources = ["${local.bucket_arn}/*"]
  }

  statement {
    sid       = "DecryptObjects"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]

    # Only by way of S3, and only for objects in this bucket.
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = [local.bucket_arn, "${local.bucket_arn}/*"]
    }
  }
}

data "aws_iam_policy_document" "write" {
  source_policy_documents = [data.aws_iam_policy_document.read.json]

  statement {
    sid = "WriteObjects"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
      "s3:PutObjectTagging",
    ]
    resources = ["${local.bucket_arn}/*"]
  }

  statement {
    sid       = "EncryptObjects"
    actions   = ["kms:GenerateDataKey"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = [local.bucket_arn, "${local.bucket_arn}/*"]
    }
  }
}
