###############################################################################
# BOOTSTRAP - run this ONCE, before envs/dev
#
# Creates the S3 bucket (and optional DynamoDB lock table) that hold the
# Terraform remote state. This stack itself uses LOCAL state, because the
# backend cannot store its own state before the bucket exists.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60.0, < 7.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Owner     = var.owner
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are globally unique, so the account ID is appended.
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "tf_state" {
  bucket = local.bucket_name

  # force_destroy = false protects the state file from accidental deletion.
  force_destroy = false

  tags = {
    Name = local.bucket_name
  }
}

# Versioning is what lets you roll back a corrupted or truncated state file.
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# COST: state files are small, but every apply writes a new version.
# Old versions are cleaned up automatically after 30 days.
resource "aws_s3_bucket_lifecycle_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.tf_state]
}

###############################################################################
# STATE LOCKING
# Terraform 1.10+ can lock using an S3 object (use_lockfile = true), so the
# DynamoDB table is optional. It is created by default for compatibility
# with older Terraform versions on a teammate's machine.
###############################################################################

resource "aws_dynamodb_table" "tf_lock" {
  count = var.create_dynamodb_lock_table ? 1 : 0

  name         = "${var.project}-tf-locks"
  billing_mode = "PAY_PER_REQUEST" # COST: no idle charge, pennies per apply
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "${var.project}-tf-locks"
  }
}
