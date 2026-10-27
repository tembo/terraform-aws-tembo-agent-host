variable "region" {
  type        = string
  description = "AWS region."
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones for the VPC's subnets."
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version of the example cluster."
}

variable "kubernetes_namespace" {
  type        = string
  description = "Namespace the tembo chart is installed in."
}

variable "identity_type" {
  type        = string
  description = "How the host controller gets its IAM role: `pod_identity` or `irsa`."
  default     = "pod_identity"
}
