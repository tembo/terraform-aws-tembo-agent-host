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

output "object_storage_bucket_name" {
  description = "The install's object storage bucket."
  value       = local.object_storage_bucket_name
}

output "object_storage_bucket_arn" {
  description = "ARN of the install's object storage bucket."
  value       = local.object_storage_bucket_arn
}

output "control_plane_role_arn" {
  description = "ARN of the control plane's role, which reads and writes the install's object storage."
  value       = one(aws_iam_role.control_plane[*].arn)
}

output "helm_values" {
  description = <<-EOT
    Values for the tembo Helm chart: its AWS settings (`provider.aws`, with EKS Auto Mode's load balancer class), the
    host controller with this module's identity, a host class and pool named `default`, and with object storage, the
    bucket and the control plane's identity.
    EOT
  # EKS injects Pod Identity credentials when a pod is created, so the chart
  # must install after the associations and the roles' permissions exist.
  depends_on = [
    aws_eks_pod_identity_association.controller,
    aws_iam_role_policy.controller,
    aws_eks_pod_identity_association.control_plane,
    aws_iam_role_policy.control_plane,
  ]
  value = local.enabled ? merge({
    compute = {
      mode = "controller"
      controller = {
        clusterName  = var.cluster_name
        apiServerUrl = local.cluster_endpoint
        serviceAccount = {
          annotations = var.identity_type == "irsa" ? { "eks.amazonaws.com/role-arn" = one(aws_iam_role.controller[*].arn) } : {}
        }
      }
      hostClasses = { default = local.host_class }
      hostPools = {
        default = {
          classRef = { name = "default" }
          # Hosts that stay up, ready for sessions.
          minHosts = 1
          maxHosts = 3
          # Free memory to keep for new sessions before adding a host.
          minIdleMemory = "32Gi"
        }
      }
    }
    },
    {
      provider = {
        aws = merge(
          { enabled = true },
          # EKS Auto Mode creates load balancers only for its own class. Lists,
          # empty when off, avoid a conditional between unlike objects.
          [for values in [{ loadBalancerClass = "eks.amazonaws.com/nlb" }] : values if local.cluster_auto_mode]...
        )
      }
    },
    [for values in [{
      objectStorage = {
        bucket = local.object_storage_bucket_name
        region = local.object_storage_region
      }
      serviceAccount = {
        annotations = var.identity_type == "irsa" ? { "eks.amazonaws.com/role-arn" = one(aws_iam_role.control_plane[*].arn) } : {}
      }
    }] : values if local.object_storage_enabled]...
  ) : null
}

output "host_class" {
  description = <<-EOT
    A host class using this module's subnets, security groups, instance profile and image parameter, for the chart's
    `compute.hostClasses.<name>`. `helm_values` already sets one named `default`.
    EOT
  value       = local.host_class
}
