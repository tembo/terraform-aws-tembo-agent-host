# Plan-only tests against a mocked AWS provider: terraform test (or tofu test).
# Overrides of nested data source attributes must list every field, so a
# provider release adding one needs it added here.

mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/mock"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::111111111111:instance-profile/mock"
    }
  }

  override_data {
    target = data.aws_eks_cluster.this
    values = {
      arn      = "arn:aws:eks:us-east-2:111111111111:cluster/example"
      endpoint = "https://EXAMPLE.gr7.us-east-2.eks.amazonaws.com"
      vpc_config = [{
        cluster_security_group_id = "sg-cluster"
        control_plane_egress_mode = "Standard"
        endpoint_private_access   = true
        endpoint_public_access    = true
        public_access_cidrs       = []
        security_group_ids        = []
        subnet_ids                = []
        vpc_id                    = "vpc-example"
      }]
      identity = [{
        oidc = [{ issuer = "https://oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE" }]
      }]
    }
  }

  override_data {
    target = data.aws_iam_openid_connect_provider.cluster
    values = {
      arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"
    }
  }

  # The mock's random strings are not valid policy JSON.
  override_data {
    target = data.aws_iam_policy_document.controller_trust
    values = { json = "{}" }
  }
  override_data {
    target = data.aws_iam_policy_document.controller
    values = { json = "{}" }
  }
  override_data {
    target = data.aws_iam_policy_document.host_trust
    values = { json = "{}" }
  }
  override_data {
    target = data.aws_iam_policy_document.host_object_storage
    values = { json = "{}" }
  }
}

variables {
  namespace            = "eg"
  name                 = "agent-host"
  cluster_name         = "example"
  kubernetes_namespace = "tembo"
  vpc_id               = "vpc-example"
  host_subnet_ids      = ["subnet-a", "subnet-b"]
  image_parameter_arn  = "arn:aws:ssm:us-east-2:222222222222:parameter/tembo/agent-host/ami"
}

run "pod_identity" {
  command = plan

  assert {
    condition     = length(aws_eks_pod_identity_association.controller) == 1
    error_message = "Expected a Pod Identity association."
  }

  assert {
    condition     = aws_eks_pod_identity_association.controller[0].service_account == "tembo-host-controller"
    error_message = "Expected the chart's service account for release tembo."
  }

  assert {
    condition     = aws_eks_pod_identity_association.controller[0].namespace == "tembo"
    error_message = "Expected the release namespace."
  }

  assert {
    condition     = length(output.helm_values.compute.controller.serviceAccount.annotations) == 0
    error_message = "Pod Identity needs no service account annotation."
  }

  assert {
    condition     = output.helm_values.compute.controller.apiServerUrl == "https://EXAMPLE.gr7.us-east-2.eks.amazonaws.com"
    error_message = "Expected the cluster endpoint as the host API server."
  }

  assert {
    condition = output.ownership_tags == tomap({
      "hosts.tembo.io/cluster"   = "example"
      "hosts.tembo.io/namespace" = "tembo"
    })
    error_message = "Expected ownership tags for the cluster and namespace."
  }

  assert {
    condition     = jsonencode(output.host_class.aws.subnetSelectorTerms) == jsonencode([{ id = "subnet-a" }, { id = "subnet-b" }])
    error_message = "Expected a subnet term per subnet ID."
  }

  assert {
    condition     = jsonencode(output.host_class.aws.imageSelectorTerms) == jsonencode([{ ssmParameter = "arn:aws:ssm:us-east-2:222222222222:parameter/tembo/agent-host/ami" }])
    error_message = "Expected the image parameter as the image term."
  }

  assert {
    condition     = output.host_class.aws.instanceProfile == "eg-agent-host-host"
    error_message = "Expected the module's instance profile."
  }

  assert {
    condition     = jsonencode(keys(aws_vpc_security_group_ingress_rule.manager_from_security_groups)) == jsonencode(["cluster"])
    error_message = "Expected manager ingress from the cluster security group by default."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.manager_from_security_groups["cluster"].referenced_security_group_id == "sg-cluster"
    error_message = "Expected manager ingress from the cluster security group by default."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cluster_api[0].security_group_id == "sg-cluster"
    error_message = "Expected Kubernetes API ingress on the cluster security group."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.host_ssm) == 1
    error_message = "Expected Session Manager access by default."
  }
}

run "irsa" {
  command = plan

  variables {
    identity_type = "irsa"
    release_name  = "prod"
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.controller) == 0
    error_message = "IRSA needs no Pod Identity association."
  }

  assert {
    condition     = output.service_account_name == "prod-tembo-host-controller"
    error_message = "Expected the chart's service account for release prod."
  }

  assert {
    condition     = contains(keys(output.helm_values.compute.controller.serviceAccount.annotations), "eks.amazonaws.com/role-arn")
    error_message = "IRSA needs the role annotation."
  }
}

run "subnet_tags" {
  command = plan

  variables {
    host_subnet_ids  = []
    host_subnet_tags = { "karpenter.sh/discovery" = "example" }
  }

  assert {
    condition     = jsonencode(output.host_class.aws.subnetSelectorTerms) == jsonencode([{ tags = { "karpenter.sh/discovery" = "example" } }])
    error_message = "Expected a single tag subnet term."
  }
}

run "existing_network_and_role" {
  command = plan

  variables {
    create_security_group              = false
    security_group_ids                 = ["sg-hosts"]
    create_host_role                   = false
    host_instance_profile_name         = "hosts"
    host_role_arn                      = "arn:aws:iam::111111111111:role/hosts"
    manager_ingress_security_group_ids = ["sg-api"]
  }

  assert {
    condition     = length(aws_security_group.host) == 0 && length(aws_vpc_security_group_ingress_rule.manager_from_security_groups) == 0
    error_message = "Expected no security group or rules."
  }

  assert {
    condition     = length(aws_iam_role.host) == 0 && length(aws_iam_instance_profile.host) == 0
    error_message = "Expected no host role."
  }

  assert {
    condition     = jsonencode(output.host_class.aws.securityGroupSelectorTerms) == jsonencode([{ id = "sg-hosts" }])
    error_message = "Expected the existing security group."
  }

  assert {
    condition     = output.host_class.aws.instanceProfile == "hosts"
    error_message = "Expected the existing instance profile."
  }
}

run "host_access_and_storage" {
  command = plan

  variables {
    host_access_rules = [
      { security_group_id = "sg-rds", port = 5432, description = "Postgres from Tembo agent hosts" },
      { security_group_id = "sg-redis", port = 6379, description = "Redis from Tembo agent hosts" },
    ]
    host_object_storage_bucket_arns = ["arn:aws:s3:::snapshots"]
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.host_access["0"].security_group_id == "sg-rds" && aws_vpc_security_group_ingress_rule.host_access["0"].from_port == 5432
    error_message = "Expected Postgres ingress on the RDS security group."
  }

  assert {
    condition     = length(aws_iam_role_policy.host_object_storage) == 1
    error_message = "Expected the object storage policy."
  }
}

run "subnets_required" {
  command = plan

  variables {
    host_subnet_ids = []
  }

  expect_failures = [aws_iam_role.controller]
}

run "disabled" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_iam_role.controller) == 0 && length(aws_security_group.host) == 0 && output.helm_values == null
    error_message = "Expected nothing when disabled."
  }
}

run "default_name" {
  command = plan

  variables {
    namespace = null
    name      = null
  }

  assert {
    condition     = aws_iam_role.controller[0].name == "tembo-controller" && aws_iam_role.host[0].name == "tembo-host"
    error_message = "Expected names from the default label name."
  }
}
