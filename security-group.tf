# The host security group. Hosts are launched outside Terraform, so the group
# must never be replaced: rules are separate resources, changed in place.

resource "aws_security_group" "host" {
  count = local.enabled && var.create_security_group ? 1 : 0

  name        = module.host_label.id
  description = "Tembo agent hosts launched by ${var.kubernetes_namespace}/${local.service_account_name} in ${var.cluster_name}"
  vpc_id      = var.vpc_id
  tags        = module.host_label.tags
}

resource "aws_vpc_security_group_ingress_rule" "manager_from_security_groups" {
  for_each = local.enabled && var.create_security_group ? local.manager_ingress_security_group_ids : {}

  security_group_id            = one(aws_security_group.host[*].id)
  description                  = "Host manager API from the Tembo API and host controller"
  ip_protocol                  = "tcp"
  from_port                    = 8743
  to_port                      = 8743
  referenced_security_group_id = each.value
  tags                         = module.host_label.tags
}

resource "aws_vpc_security_group_ingress_rule" "manager_from_cidrs" {
  for_each = local.enabled && var.create_security_group ? { for i, cidr in var.manager_ingress_cidr_blocks : tostring(i) => cidr } : {}

  security_group_id = one(aws_security_group.host[*].id)
  description       = "Host manager API"
  ip_protocol       = "tcp"
  from_port         = 8743
  to_port           = 8743
  cidr_ipv4         = each.value
  tags              = module.host_label.tags
}

# Hosts reach the Tembo API, the Kubernetes API, Postgres, Redis, object
# storage, LLM endpoints and code hosts.
resource "aws_vpc_security_group_egress_rule" "all" {
  count = local.enabled && var.create_security_group ? 1 : 0

  security_group_id = one(aws_security_group.host[*].id)
  description       = "All egress"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = module.host_label.tags
}

# Hosts read their configuration through the cluster's Kubernetes API.
resource "aws_vpc_security_group_ingress_rule" "cluster_api" {
  count = local.enabled && var.create_security_group && var.cluster_api_ingress_enabled ? 1 : 0

  security_group_id            = local.cluster_security_group_id
  description                  = "Kubernetes API from Tembo agent hosts"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = one(aws_security_group.host[*].id)
  tags                         = module.host_label.tags
}

resource "aws_vpc_security_group_ingress_rule" "host_access" {
  for_each = local.enabled && var.create_security_group ? { for i, rule in var.host_access_rules : tostring(i) => rule } : {}

  security_group_id            = each.value.security_group_id
  description                  = each.value.description
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = one(aws_security_group.host[*].id)
  tags                         = module.host_label.tags
}
