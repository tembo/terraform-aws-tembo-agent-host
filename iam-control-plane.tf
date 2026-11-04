# The control plane's role: the API, worker and cron, which share the chart's
# service account, read and write the install's object storage.

locals {
  control_plane_service_account_name = coalesce(var.control_plane_service_account_name, local.release_fullname)
}

module "control_plane_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  name            = local.label_name
  attributes      = ["control-plane"]
  id_length_limit = 64

  context = module.this.context
}

data "aws_iam_policy_document" "control_plane_trust" {
  count = local.object_storage_enabled ? 1 : 0

  dynamic "statement" {
    for_each = var.identity_type == "pod_identity" ? [1] : []
    content {
      sid     = "EKSPodIdentity"
      effect  = "Allow"
      actions = ["sts:AssumeRole", "sts:TagSession"]

      principals {
        type        = "Service"
        identifiers = ["pods.eks.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }

      condition {
        test     = "ArnEquals"
        variable = "aws:SourceArn"
        values   = [local.cluster_arn]
      }
    }
  }

  dynamic "statement" {
    for_each = var.identity_type == "irsa" ? [1] : []
    content {
      sid     = "IRSA"
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [coalesce(var.oidc_provider_arn, local.cluster_oidc_provider_arn)]
      }

      condition {
        test     = "StringEquals"
        variable = "${local.cluster_oidc_provider}:sub"
        values   = ["system:serviceaccount:${var.kubernetes_namespace}:${local.control_plane_service_account_name}"]
      }

      condition {
        test     = "StringEquals"
        variable = "${local.cluster_oidc_provider}:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }
}

data "aws_iam_policy_document" "control_plane" {
  count = local.object_storage_enabled ? 1 : 0

  statement {
    sid       = "ListStorageBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.object_storage_bucket_arn]
  }

  statement {
    sid    = "ReadWriteStorage"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${local.object_storage_bucket_arn}/*"]
  }
}

resource "aws_iam_role" "control_plane" {
  count = local.object_storage_enabled ? 1 : 0

  name               = module.control_plane_label.id
  description        = "Tembo control plane (${var.kubernetes_namespace}/${local.control_plane_service_account_name} in ${var.cluster_name}): object storage"
  assume_role_policy = one(data.aws_iam_policy_document.control_plane_trust[*].json)
  tags               = module.control_plane_label.tags
}

resource "aws_iam_role_policy" "control_plane" {
  count = local.object_storage_enabled ? 1 : 0

  name   = module.control_plane_label.id
  role   = one(aws_iam_role.control_plane[*].id)
  policy = one(data.aws_iam_policy_document.control_plane[*].json)
}

resource "aws_eks_pod_identity_association" "control_plane" {
  count = local.object_storage_enabled && var.identity_type == "pod_identity" ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.kubernetes_namespace
  service_account = local.control_plane_service_account_name
  role_arn        = one(aws_iam_role.control_plane[*].arn)
  tags            = module.control_plane_label.tags
}
