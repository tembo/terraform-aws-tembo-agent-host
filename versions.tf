terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws_eks_pod_identity_association arrived in 5.36.
      version = ">= 5.36, < 7.0"
    }
  }
}
