output "controller_role_arn" {
  description = "ARN of the host controller's IAM role."
  value       = one(aws_iam_role.controller[*].arn)
}

output "controller_role_name" {
  description = "Name of the host controller's IAM role."
  value       = one(aws_iam_role.controller[*].name)
}

output "service_account_name" {
  description = "Host controller service account the role is bound to."
  value       = local.enabled ? local.service_account_name : null
}

output "host_role_arn" {
  description = "ARN of the agent host IAM role."
  value       = local.enabled ? local.host_role_arn : null
}

output "host_instance_profile_name" {
  description = "Instance profile agent hosts launch with."
  value       = local.enabled ? local.host_instance_profile : null
}

output "host_security_group_id" {
  description = "ID of the host security group the module creates."
  value       = one(aws_security_group.host[*].id)
}

output "security_group_ids" {
  description = "All security groups agent hosts launch with."
  value       = local.enabled ? local.host_security_group_ids : []
}

output "ownership_tags" {
  description = "Tags the host controller puts on, and requires of, the instances and volumes it manages."
  value       = local.enabled ? local.ownership_tags : {}
}

output "helm_values" {
  description = "Values for the tembo Helm chart that install the host controller with this module's identity."
  value = local.enabled ? {
    compute = {
      mode = "controller"
      controller = {
        clusterName  = var.cluster_name
        apiServerUrl = local.cluster_endpoint
        serviceAccount = {
          annotations = var.identity_type == "irsa" ? { "eks.amazonaws.com/role-arn" = one(aws_iam_role.controller[*].arn) } : {}
        }
      }
    }
  } : null
}

output "host_class" {
  description = <<-EOT
    A host class using this module's subnets, security groups, instance profile and image parameter, for the chart's
    `compute.hostClasses.<name>`. Host classes need the chart's CRDs, so add them in an upgrade after the first install.
    EOT
  value = local.enabled ? {
    aws = merge(
      var.image_parameter_arn != null ? { imageSelectorTerms = [{ ssmParameter = var.image_parameter_arn }] } : {},
      {
        instanceTypes              = var.instance_types
        subnetSelectorTerms        = concat([for id in var.host_subnet_ids : { id = id }], length(var.host_subnet_tags) > 0 ? [{ tags = var.host_subnet_tags }] : [])
        securityGroupSelectorTerms = [for id in local.host_security_group_ids : { id = id }]
        instanceProfile            = local.host_instance_profile
      },
    )
  } : null
}
