locals {
  enabled = module.this.enabled

  # The chart's fullname: the release name, suffixed with the chart name
  # unless it already contains it.
  release_fullname     = trimsuffix(substr(strcontains(var.release_name, "tembo") ? var.release_name : "${var.release_name}-tembo", 0, 63), "-")
  service_account_name = coalesce(var.service_account_name, "${local.release_fullname}-host-controller")

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

  host_security_group_ids = concat(aws_security_group.host[*].id, var.security_group_ids)
  host_role_arn           = var.create_host_role ? one(aws_iam_role.host[*].arn) : var.host_role_arn
  host_instance_profile   = var.create_host_role ? one(aws_iam_instance_profile.host[*].name) : var.host_instance_profile_name

  # Keyed by position, or "cluster" for the default, so keys are known at plan
  # time even while the cluster is being created.
  manager_ingress_security_group_ids = (
    var.manager_ingress_security_group_ids != null
    ? { for i, id in var.manager_ingress_security_group_ids : tostring(i) => id }
    : { cluster = local.cluster_security_group_id }
  )
}

data "aws_eks_cluster" "this" {
  count = local.enabled ? 1 : 0

  name = var.cluster_name
}

module "controller_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  name            = local.label_name
  attributes      = ["controller"]
  id_length_limit = 64

  context = module.this.context
}

module "host_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  name            = local.label_name
  attributes      = ["host"]
  id_length_limit = 64

  context = module.this.context
}
