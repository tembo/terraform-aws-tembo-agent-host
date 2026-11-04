# The install's object storage: one bucket for project builds (VM golden
# snapshots), file uploads and agent assets. Agent hosts and the control plane
# get read and write access; browsers upload through presigned URLs, so the
# bucket allows the install's origins.

locals {
  object_storage_enabled     = local.enabled && var.object_storage_enabled
  create_object_storage      = local.object_storage_enabled && var.object_storage_bucket_name == null
  object_storage_bucket_name = local.object_storage_enabled ? coalesce(var.object_storage_bucket_name, module.storage_label.id) : null
  object_storage_bucket_arn  = local.object_storage_enabled ? "arn:${local.partition}:s3:::${local.object_storage_bucket_name}" : null
  object_storage_region      = local.create_object_storage ? one(aws_s3_bucket.storage[*].region) : local.region

  host_object_storage_bucket_arns = concat(compact([local.object_storage_bucket_arn]), var.host_object_storage_bucket_arns)
}

module "storage_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  name            = local.label_name
  attributes      = ["storage"]
  id_length_limit = 63

  context = module.this.context
}

resource "aws_s3_bucket" "storage" {
  count = local.create_object_storage ? 1 : 0

  bucket        = local.object_storage_bucket_name
  force_destroy = var.object_storage_force_destroy
  tags          = module.storage_label.tags
}

resource "aws_s3_bucket_public_access_block" "storage" {
  count = local.create_object_storage ? 1 : 0

  bucket                  = one(aws_s3_bucket.storage[*].id)
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "storage" {
  count = local.create_object_storage ? 1 : 0

  bucket = one(aws_s3_bucket.storage[*].id)
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "storage" {
  count = local.create_object_storage ? 1 : 0

  bucket = one(aws_s3_bucket.storage[*].id)
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Snapshots upload in parts; drop parts an interrupted upload leaves behind.
resource "aws_s3_bucket_lifecycle_configuration" "storage" {
  count = local.create_object_storage ? 1 : 0

  bucket = one(aws_s3_bucket.storage[*].id)
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "storage" {
  count = local.create_object_storage && length(var.object_storage_cors_allowed_origins) > 0 ? 1 : 0

  bucket = one(aws_s3_bucket.storage[*].id)
  cors_rule {
    allowed_origins = var.object_storage_cors_allowed_origins
    allowed_methods = ["GET", "PUT", "DELETE", "HEAD"]
    allowed_headers = ["*"]
    max_age_seconds = 3600
  }
}
