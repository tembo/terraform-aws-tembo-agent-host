variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the Tembo install runs in."
}

variable "kubernetes_namespace" {
  type        = string
  description = "Kubernetes namespace of the Tembo install (the tembo Helm release)."
}

variable "release_name" {
  type        = string
  description = "Name of the tembo Helm release, which names the host controller's service account."
  default     = "tembo"
}

variable "service_account_name" {
  type        = string
  description = <<-EOT
    Overrides the host controller's service account name. Defaults to the chart's: `<release_name>-host-controller` when the
    release name contains `tembo`, otherwise `<release_name>-tembo-host-controller`.
    EOT
  default     = null
}

variable "identity_type" {
  type        = string
  description = <<-EOT
    How the host controller gets its IAM role: `pod_identity` (EKS Pod Identity, the default) or `irsa` (IAM roles for
    service accounts). Pod Identity needs the EKS Pod Identity agent, which EKS Auto Mode includes.
    EOT
  default     = "pod_identity"

  validation {
    condition     = contains(["pod_identity", "irsa"], var.identity_type)
    error_message = "identity_type must be pod_identity or irsa."
  }
}

variable "oidc_provider_arn" {
  type        = string
  description = <<-EOT
    IAM OIDC provider for the cluster, for `identity_type = "irsa"`. Defaults to the provider named after the cluster's
    issuer. Pass the provider's ARN when it is created in the same apply, so the role is created after it.
    EOT
  default     = null
}

variable "host_subnet_ids" {
  type        = list(string)
  description = "Subnets agent hosts launch into. Set this or `host_subnet_tags`."
  default     = []
}

variable "host_subnet_tags" {
  type        = map(string)
  description = <<-EOT
    Tags selecting the subnets agent hosts launch into, such as an existing `karpenter.sh/discovery` tag. Set this or
    `host_subnet_ids`. The module does not tag subnets.
    EOT
  default     = {}
}

variable "vpc_id" {
  type        = string
  description = "VPC of the host security group. Required when `create_security_group` is true."
  default     = null
}

variable "create_security_group" {
  type        = bool
  description = "Create the host security group. When false, set `security_group_ids`."
  default     = true
}

variable "security_group_ids" {
  type        = list(string)
  description = "Existing security groups for agent hosts, used with or instead of the module's group."
  default     = []
}

variable "manager_ingress_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    Security groups allowed to reach each host's manager on port 8743: the Tembo API and host controller pods. Defaults
    to the cluster security group, which EKS pods and nodes use unless security groups for pods are configured.
    EOT
  default     = null
}

variable "manager_ingress_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to reach each host's manager on port 8743, in addition to the security groups."
  default     = []
}

variable "cluster_api_ingress_enabled" {
  type        = bool
  description = <<-EOT
    Allow agent hosts to reach the cluster's Kubernetes API (port 443 on the cluster security group). Hosts read their
    configuration through it at boot.
    EOT
  default     = true
}

variable "host_access_rules" {
  type = list(object({
    security_group_id = string
    port              = number
    description       = string
  }))
  description = <<-EOT
    Ingress rules added to existing security groups so agent hosts can reach them, such as RDS (5432), ElastiCache (6379)
    or an internal load balancer.
    EOT
  default     = []
}

variable "create_host_role" {
  type        = bool
  description = "Create the agent host IAM role and instance profile. When false, set `host_instance_profile_name` and `host_role_arn`."
  default     = true
}

variable "host_instance_profile_name" {
  type        = string
  description = "Existing instance profile for agent hosts, when `create_host_role` is false."
  default     = null
}

variable "host_role_arn" {
  type        = string
  description = "Role of the existing instance profile, when `create_host_role` is false. The controller may pass only this role."
  default     = null
}

variable "host_ssm_enabled" {
  type        = bool
  description = "Attach `AmazonSSMManagedInstanceCore` to the host role, for access through Session Manager."
  default     = true
}

variable "host_policy_arns" {
  type        = list(string)
  description = "Additional managed policies for the host role."
  default     = []
}

variable "host_object_storage_bucket_arns" {
  type        = list(string)
  description = "S3 buckets agent hosts read and write session snapshots in, when they use instance-profile credentials."
  default     = []
}

variable "image_parameter_arn" {
  type        = string
  description = "SSM parameter publishing the agent host image ID, shared by Tembo. The controller may read only this parameter."
  default     = null
}

variable "volume_kms_key_arns" {
  type        = list(string)
  description = "Customer-managed KMS keys host volumes are encrypted with. Not needed for AWS-managed keys."
  default     = []
}

variable "instance_types" {
  type        = list(string)
  description = "Instance types for the default host class in `helm_values`, in order of preference. They must provide /dev/kvm."
  default     = ["m8i.4xlarge"]
}
