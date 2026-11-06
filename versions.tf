terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # The EKS cluster's compute_config (Auto Mode) arrived in 5.79.
      version = ">= 5.79, < 7.0"
    }
  }
}
