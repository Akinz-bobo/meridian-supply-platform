# Account-wide settings that make the safe choice the default for anything
# created in the account, including things created outside Terraform.
#
# Each one is a backstop. Modules already encrypt volumes and block public
# buckets themselves, and these settings catch the resource that someone
# creates by hand or with a module that forgot.

# No bucket in the account can be made public, whatever its own settings.
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Every new EBS volume and snapshot is encrypted, with the given key.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "this" {
  key_arn = var.ebs_kms_key_arn

  depends_on = [aws_ebs_encryption_by_default.this]
}

# Reports any resource policy that grants access to a principal outside
# the account: a bucket, key, role, queue or secret shared too widely.
resource "aws_accessanalyzer_analyzer" "this" {
  analyzer_name = var.name
  type          = "ACCOUNT"

  tags = var.tags
}

# People do not have users in this account, so this policy should never be
# exercised. It is set so that a user created in an emergency is not
# protected by a weak password.
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = var.minimum_password_length
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
}
