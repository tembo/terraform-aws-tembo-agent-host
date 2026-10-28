output "cluster_name" {
  description = "Name of the example cluster."
  value       = module.eks_cluster.eks_cluster_id
}

output "controller_role_arn" {
  description = "ARN of the host controller's IAM role."
  value       = module.agent_host.controller_role_arn
}

output "service_account_name" {
  description = "Host controller service account the role is bound to."
  value       = module.agent_host.service_account_name
}

output "host_role_arn" {
  description = "ARN of the agent host IAM role."
  value       = module.agent_host.host_role_arn
}

output "host_instance_profile_name" {
  description = "Instance profile agent hosts launch with."
  value       = module.agent_host.host_instance_profile_name
}

output "host_security_group_id" {
  description = "ID of the host security group."
  value       = module.agent_host.host_security_group_id
}

output "ownership_tags" {
  description = "Tags the host controller puts on, and requires of, its instances."
  value       = module.agent_host.ownership_tags
}

output "helm_values" {
  description = "Values for the tembo Helm chart."
  value       = module.agent_host.helm_values
}

output "host_class" {
  description = "A host class for the chart's `compute.hostClasses.<name>`."
  value       = module.agent_host.host_class
}
