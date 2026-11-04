locals {
  enabled = module.this.enabled

  # The chart's fullname: the release name, suffixed with the chart name
  # unless it already contains it.
  release_fullname = trimsuffix(substr(strcontains(var.release_name, "tembo") ? var.release_name : "${var.release_name}-tembo", 0, 63), "-")

  # Names roles "tembo-controller" and "tembo-host" without a name in the context.
  label_name = coalesce(module.this.name, "tembo")

  # The controller tags every host with its cluster and namespace, and may only
  # launch and terminate instances carrying both.
  ownership_tags = {
    "hosts.tembo.io/cluster"   = var.cluster_name
    "hosts.tembo.io/namespace" = var.kubernetes_namespace
  }

  cluster_arn               = one(data.aws_eks_cluster.this[*].arn)
  cluster_endpoint          = one(data.aws_eks_cluster.this[*].endpoint)
  cluster_security_group_id = one(data.aws_eks_cluster.this[*].vpc_config[0].cluster_security_group_id)
  cluster_oidc_issuer       = one(data.aws_eks_cluster.this[*].identity[0].oidc[0].issuer)

  # arn:<partition>:eks:<region>:<account>:cluster/<name>
  cluster_arn_parts = split(":", coalesce(local.cluster_arn, "arn:aws:eks:*:*:cluster/*"))
  partition         = local.cluster_arn_parts[1]
  region            = local.cluster_arn_parts[3]
  account_id        = local.cluster_arn_parts[4]
  ec2_arn           = "arn:${local.partition}:ec2:${local.region}"

  # IAM names a cluster's OIDC provider after its issuer, so its ARN is known
  # without a lookup, which would fail for a provider created in the same apply.
  cluster_oidc_provider     = trimprefix(coalesce(local.cluster_oidc_issuer, "https://"), "https://")
  cluster_oidc_provider_arn = "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.cluster_oidc_provider}"
}

data "aws_eks_cluster" "this" {
  count = local.enabled ? 1 : 0

  name = var.cluster_name
}
