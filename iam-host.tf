# The role agent hosts launch with. Hosts read their configuration from the
# Kubernetes API, not through IAM, so the role only carries optional access:
# Session Manager, object storage and any extra policies.

data "aws_iam_policy_document" "host_trust" {
  count = local.enabled && var.create_host_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "host" {
  count = local.enabled && var.create_host_role ? 1 : 0

  name               = module.host_label.id
  description        = "Tembo agent hosts launched by ${var.kubernetes_namespace}/${local.service_account_name} in ${var.cluster_name}"
  assume_role_policy = one(data.aws_iam_policy_document.host_trust[*].json)
  tags               = module.host_label.tags
}

resource "aws_iam_role_policy_attachment" "host_ssm" {
  count = local.enabled && var.create_host_role && var.host_ssm_enabled ? 1 : 0

  role       = one(aws_iam_role.host[*].name)
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "host_extra" {
  for_each = local.enabled && var.create_host_role ? { for i, arn in var.host_policy_arns : tostring(i) => arn } : {}

  role       = one(aws_iam_role.host[*].name)
  policy_arn = each.value
}

data "aws_iam_policy_document" "host_object_storage" {
  count = local.enabled && var.create_host_role && length(var.host_object_storage_bucket_arns) > 0 ? 1 : 0

  statement {
    sid       = "ListSnapshotBuckets"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = var.host_object_storage_bucket_arns
  }

  statement {
    sid    = "ReadWriteSnapshots"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [for arn in var.host_object_storage_bucket_arns : "${arn}/*"]
  }
}

resource "aws_iam_role_policy" "host_object_storage" {
  count = local.enabled && var.create_host_role && length(var.host_object_storage_bucket_arns) > 0 ? 1 : 0

  name   = "${module.host_label.id}-object-storage"
  role   = one(aws_iam_role.host[*].id)
  policy = one(data.aws_iam_policy_document.host_object_storage[*].json)
}

resource "aws_iam_instance_profile" "host" {
  count = local.enabled && var.create_host_role ? 1 : 0

  name = module.host_label.id
  role = one(aws_iam_role.host[*].name)
  tags = module.host_label.tags
}
