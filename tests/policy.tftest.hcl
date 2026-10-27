# Plan-only tests of the rendered IAM policies. aws_iam_policy_document renders
# offline, so this uses the real provider with placeholder credentials and
# overrides only the lookups that would call AWS.

provider "aws" {
  region                      = "us-east-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
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

# Existing host role and security groups keep every policy input known at plan.
variables {
  namespace                  = "eg"
  name                       = "agent-host"
  cluster_name               = "example"
  kubernetes_namespace       = "tembo"
  host_subnet_ids            = ["subnet-a"]
  create_security_group      = false
  security_group_ids         = ["sg-hosts"]
  create_host_role           = false
  host_instance_profile_name = "hosts"
  host_role_arn              = "arn:aws:iam::111111111111:role/hosts"
  image_parameter_arn        = "arn:aws:ssm:us-east-2:222222222222:parameter/tembo/agent-host/ami"
}

run "controller_policy" {
  command = plan

  variables {
    volume_kms_key_arns = ["arn:aws:kms:us-east-2:111111111111:key/example"]
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "RunInstancesHostSubnets"]).Resource == "arn:aws:ec2:us-east-2:111111111111:subnet/subnet-a" &&
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "RunInstancesHostSecurityGroups"]).Resource == "arn:aws:ec2:us-east-2:111111111111:security-group/sg-hosts"
    )
    error_message = "Expected RunInstances limited to the host subnets and security groups."
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "RunOwnedInstances"]).Condition.StringEquals["aws:RequestTag/hosts.tembo.io/cluster"] == "example" &&
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "RunOwnedInstances"]).Condition.StringEquals["aws:RequestTag/hosts.tembo.io/namespace"] == "tembo" &&
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "TagOnLaunch"]).Condition.StringEquals["ec2:CreateAction"] == "RunInstances"
    )
    error_message = "Expected launches and tags to require the ownership tags."
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "TerminateOwnedInstances"]).Condition.StringEquals["ec2:ResourceTag/hosts.tembo.io/cluster"] == "example" &&
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "TerminateOwnedInstances"]).Condition.StringEquals["ec2:ResourceTag/hosts.tembo.io/namespace"] == "tembo"
    )
    error_message = "Expected termination limited to owned instances."
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "PassHostRole"]).Resource == "arn:aws:iam::111111111111:role/hosts" &&
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "PassHostRole"]).Condition.StringEquals["iam:PassedToService"] == "ec2.amazonaws.com"
    )
    error_message = "Expected PassRole limited to the host role, for EC2."
  }

  assert {
    condition     = one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "ReadImageParameter"]).Resource == "arn:aws:ssm:us-east-2:222222222222:parameter/tembo/agent-host/ami"
    error_message = "Expected the image parameter to be readable."
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "UseVolumeKeys"]).Condition.StringEquals["kms:ViaService"] == "ec2.us-east-2.amazonaws.com" &&
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "GrantVolumeKeysToEC2"]).Condition.Bool["kms:GrantIsForAWSResource"] == "true"
    )
    error_message = "Expected volume keys usable only through EC2."
  }
}

run "subnet_tags_policy" {
  command = plan

  variables {
    host_subnet_ids  = []
    host_subnet_tags = { "karpenter.sh/discovery" = "example" }
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "RunInstancesHostSubnets"]).Resource == "arn:aws:ec2:us-east-2:111111111111:subnet/*" &&
      one([for s in jsondecode(data.aws_iam_policy_document.controller[0].json).Statement : s if s.Sid == "RunInstancesHostSubnets"]).Condition.StringLike["ec2:ResourceTag/karpenter.sh/discovery"] == "example"
    )
    error_message = "Expected RunInstances limited to subnets with the tags."
  }
}

run "pod_identity_trust" {
  command = plan

  assert {
    condition = (
      jsondecode(data.aws_iam_policy_document.controller_trust[0].json).Statement[0].Principal.Service == "pods.eks.amazonaws.com" &&
      jsondecode(data.aws_iam_policy_document.controller_trust[0].json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "111111111111" &&
      jsondecode(data.aws_iam_policy_document.controller_trust[0].json).Statement[0].Condition.ArnEquals["aws:SourceArn"] == "arn:aws:eks:us-east-2:111111111111:cluster/example"
    )
    error_message = "Expected the role trusted by EKS Pod Identity for this cluster only."
  }
}

run "irsa_trust" {
  command = plan

  variables {
    identity_type = "irsa"
  }

  assert {
    condition = (
      jsondecode(data.aws_iam_policy_document.controller_trust[0].json).Statement[0].Principal.Federated == "arn:aws:iam::111111111111:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE" &&
      jsondecode(data.aws_iam_policy_document.controller_trust[0].json).Statement[0].Condition.StringEquals["oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE:sub"] == "system:serviceaccount:tembo:tembo-host-controller"
    )
    error_message = "Expected the role trusted by the controller's service account only."
  }
}
