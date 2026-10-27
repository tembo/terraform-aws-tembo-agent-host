# A VPC and an EKS cluster without nodes (the module only needs the cluster),
# then the module with a stand-in database security group.

module "vpc" {
  source  = "cloudposse/vpc/aws"
  version = "3.0.0"

  ipv4_primary_cidr_block = "172.16.0.0/16"

  context = module.this.context
}

module "subnets" {
  source  = "cloudposse/dynamic-subnets/aws"
  version = "3.1.1"

  availability_zones   = var.availability_zones
  vpc_id               = module.vpc.vpc_id
  igw_id               = [module.vpc.igw_id]
  ipv4_cidr_block      = [module.vpc.vpc_cidr_block]
  max_nats             = 1
  nat_gateway_enabled  = true
  nat_instance_enabled = false

  context = module.this.context
}

module "eks_cluster" {
  source  = "cloudposse/eks-cluster/aws"
  version = "4.15.0"

  subnet_ids            = module.subnets.private_subnet_ids
  kubernetes_version    = var.kubernetes_version
  oidc_provider_enabled = var.identity_type == "irsa"

  access_config = {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  context = module.this.context

  cluster_depends_on = [module.subnets]
}

module "database_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = ["database"]

  context = module.this.context
}

resource "aws_security_group" "database" {
  count = module.this.enabled ? 1 : 0

  name        = module.database_label.id
  description = "Stand-in for a database agent hosts connect to"
  vpc_id      = module.vpc.vpc_id
  tags        = module.database_label.tags
}

module "agent_host" {
  source = "../.."

  cluster_name         = module.eks_cluster.eks_cluster_id
  kubernetes_namespace = var.kubernetes_namespace
  identity_type        = var.identity_type
  oidc_provider_arn    = var.identity_type == "irsa" ? module.eks_cluster.eks_cluster_identity_oidc_issuer_arn : null

  vpc_id          = module.vpc.vpc_id
  host_subnet_ids = module.subnets.private_subnet_ids

  host_access_rules = [for id in aws_security_group.database[*].id : {
    security_group_id = id
    port              = 5432
    description       = "Postgres from Tembo agent hosts"
  }]

  context = module.this.context
}
