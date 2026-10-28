# The host controller's role. It launches and terminates agent hosts, scoped by
# the ownership tags, and may pass only the host role.

data "aws_iam_policy_document" "controller_trust" {
  count = local.enabled ? 1 : 0

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
        values   = ["system:serviceaccount:${var.kubernetes_namespace}:${local.service_account_name}"]
      }

      condition {
        test     = "StringEquals"
        variable = "${local.cluster_oidc_provider}:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }
}

data "aws_iam_policy_document" "controller" {
  count = local.enabled ? 1 : 0

  statement {
    sid    = "Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]
  }

  # Images and their snapshots may belong to Tembo's account (a shared image).
  statement {
    sid     = "RunInstancesImages"
    effect  = "Allow"
    actions = ["ec2:RunInstances"]
    resources = [
      "${local.ec2_arn}::image/*",
      "${local.ec2_arn}::snapshot/*",
      "${local.ec2_arn}:${local.account_id}:network-interface/*",
    ]
  }

  statement {
    sid       = "RunInstancesHostSubnets"
    effect    = "Allow"
    actions   = ["ec2:RunInstances"]
    resources = length(var.host_subnet_ids) > 0 ? [for id in var.host_subnet_ids : "${local.ec2_arn}:${local.account_id}:subnet/${id}"] : ["${local.ec2_arn}:${local.account_id}:subnet/*"]

    dynamic "condition" {
      for_each = length(var.host_subnet_ids) > 0 ? {} : var.host_subnet_tags
      content {
        # StringLike, so "*" matches any value as it does in the host class.
        test     = "StringLike"
        variable = "ec2:ResourceTag/${condition.key}"
        values   = [condition.value]
      }
    }
  }

  statement {
    sid       = "RunInstancesHostSecurityGroups"
    effect    = "Allow"
    actions   = ["ec2:RunInstances"]
    resources = [for id in local.host_security_group_ids : "${local.ec2_arn}:${local.account_id}:security-group/${id}"]
  }

  statement {
    sid     = "RunOwnedInstances"
    effect  = "Allow"
    actions = ["ec2:RunInstances"]
    resources = [
      "${local.ec2_arn}:${local.account_id}:instance/*",
      "${local.ec2_arn}:${local.account_id}:volume/*",
    ]

    dynamic "condition" {
      for_each = local.ownership_tags
      content {
        test     = "StringEquals"
        variable = "aws:RequestTag/${condition.key}"
        values   = [condition.value]
      }
    }
  }

  statement {
    sid     = "TagOnLaunch"
    effect  = "Allow"
    actions = ["ec2:CreateTags"]
    resources = [
      "${local.ec2_arn}:${local.account_id}:instance/*",
      "${local.ec2_arn}:${local.account_id}:volume/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances"]
    }

    dynamic "condition" {
      for_each = local.ownership_tags
      content {
        test     = "StringEquals"
        variable = "aws:RequestTag/${condition.key}"
        values   = [condition.value]
      }
    }
  }

  statement {
    sid       = "TerminateOwnedInstances"
    effect    = "Allow"
    actions   = ["ec2:TerminateInstances"]
    resources = ["${local.ec2_arn}:${local.account_id}:instance/*"]

    dynamic "condition" {
      for_each = local.ownership_tags
      content {
        test     = "StringEquals"
        variable = "ec2:ResourceTag/${condition.key}"
        values   = [condition.value]
      }
    }
  }

  statement {
    sid       = "PassHostRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = compact([local.host_role_arn])

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  dynamic "statement" {
    for_each = var.image_parameter_arn != null ? [1] : []
    content {
      sid       = "ReadImageParameter"
      effect    = "Allow"
      actions   = ["ssm:GetParameter"]
      resources = [var.image_parameter_arn]
    }
  }

  dynamic "statement" {
    for_each = length(var.volume_kms_key_arns) > 0 ? [1] : []
    content {
      sid    = "UseVolumeKeys"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:ReEncrypt*",
      ]
      resources = var.volume_kms_key_arns

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["ec2.${local.region}.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.volume_kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "GrantVolumeKeysToEC2"
      effect    = "Allow"
      actions   = ["kms:CreateGrant"]
      resources = var.volume_kms_key_arns

      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }
}

resource "aws_iam_role" "controller" {
  count = local.enabled ? 1 : 0

  name               = module.controller_label.id
  description        = "Tembo host controller for ${var.kubernetes_namespace}/${local.service_account_name} in ${var.cluster_name}"
  assume_role_policy = one(data.aws_iam_policy_document.controller_trust[*].json)
  tags               = module.controller_label.tags

  lifecycle {
    precondition {
      condition     = (length(var.host_subnet_ids) > 0) != (length(var.host_subnet_tags) > 0)
      error_message = "Set exactly one of host_subnet_ids and host_subnet_tags."
    }
    precondition {
      condition     = var.create_security_group ? var.vpc_id != null : length(var.security_group_ids) > 0
      error_message = "Set vpc_id for the module's security group, or security_group_ids when create_security_group is false."
    }
    precondition {
      condition     = var.create_host_role || (var.host_instance_profile_name != null && var.host_role_arn != null)
      error_message = "Set host_instance_profile_name and host_role_arn when create_host_role is false."
    }
  }
}

resource "aws_iam_role_policy" "controller" {
  count = local.enabled ? 1 : 0

  name   = module.controller_label.id
  role   = one(aws_iam_role.controller[*].id)
  policy = one(data.aws_iam_policy_document.controller[*].json)
}

resource "aws_eks_pod_identity_association" "controller" {
  count = local.enabled && var.identity_type == "pod_identity" ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.kubernetes_namespace
  service_account = local.service_account_name
  role_arn        = one(aws_iam_role.controller[*].arn)
  tags            = module.controller_label.tags
}
