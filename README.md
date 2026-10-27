# terraform-aws-tembo-agent-host

Terraform module for the AWS resources Tembo's host controller needs to launch agent hosts in your account: a
tag-scoped IAM role, host instance profile and security group.

Self-hosted Tembo runs agents in VMs on dedicated EC2 instances, not in pods. The host controller, installed by the
`tembo` Helm chart with `compute.mode=controller`, launches and terminates those instances as demand changes, much like
Karpenter does for nodes. This module creates what it needs outside the cluster:

- **Controller role**: an IAM role for the controller's service account, through EKS Pod Identity (the default) or IRSA.
  It can launch instances only into the given subnets and security groups, with the host instance profile, and only
  when they carry this install's ownership tags; it can terminate only instances carrying them.
- **Host role**: the role and instance profile agent hosts launch with, with optional Session Manager access, S3 access
  for session snapshots and extra policies. Hosts read their configuration from a Kubernetes Secret, not through IAM.
- **Host security group**: the host manager port (8743) from the cluster, egress, and access from hosts to the
  Kubernetes API and, optionally, to your database, Redis or load balancers.

The module reads the cluster and does not change it beyond the security group rules above. It does not tag subnets:
select them by ID or by an existing tag, such as `karpenter.sh/discovery`.

## Usage

```hcl
module "tembo_agent_host" {
  source  = "tembo/tembo-agent-host/aws"
  version = "x.x.x"

  cluster_name         = "prod"
  kubernetes_namespace = "tembo"

  vpc_id          = "vpc-0123456789abcdef0"
  host_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

  # Shared by Tembo with your account.
  image_parameter_arn = "arn:aws:ssm:us-east-2:111111111111:parameter/tembo/agent-host/ami"

  # Let hosts reach the database and Redis.
  host_access_rules = [
    { security_group_id = "sg-0123456789abcdef0", port = 5432, description = "Postgres from Tembo agent hosts" },
    { security_group_id = "sg-0123456789abcdef1", port = 6379, description = "Redis from Tembo agent hosts" },
  ]

  namespace = "acme"
  name      = "tembo"
}
```

Pass `helm_values` to the `tembo` chart to install the controller with this identity:

```hcl
resource "helm_release" "tembo" {
  name      = "tembo"
  namespace = "tembo"
  chart     = "tembo-x.y.z.tgz" # The tembo chart from your Tembo release.

  values = [
    yamlencode(module.tembo_agent_host.helm_values),
    # Host classes need the CRDs the chart installs, so add them in a later
    # upgrade.
    # yamlencode({ compute = { hostClasses = { default = module.tembo_agent_host.host_class } } }),
  ]
}
```

`host_class` is a host class using this module's subnets, security groups, instance profile and image. The chart
installs the controller and its CRDs first, so add host classes and pools in an upgrade after the first install.

The release name and namespace must match `release_name` and `kubernetes_namespace`: the controller role trusts only
the chart's service account, and the controller tags instances with the namespace.

### Identity

`identity_type = "pod_identity"` (the default) creates an EKS Pod Identity association, which needs the EKS Pod Identity
agent; EKS Auto Mode includes it. `identity_type = "irsa"` trusts the cluster's IAM OIDC provider instead and adds the
role annotation to `helm_values`.

### Existing resources

Set `create_security_group = false` with `security_group_ids`, or `create_host_role = false` with
`host_instance_profile_name` and `host_role_arn`, to use your own. The controller role is still limited to them.

## Examples

- [`examples/complete`](examples/complete): a VPC, an EKS cluster and the module.

## Tests

`terraform test` (or `tofu test`) runs plan-only tests in [`tests`](tests), with no AWS account. The Terratest suite in
[`test/src`](test/src) applies [`examples/complete`](examples/complete) in AWS:

```sh
make -C test/src test
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5 |
| aws | >= 5.36, < 7.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.36, < 7.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| controller\_label | cloudposse/label/null | 0.25.0 |
| host\_label | cloudposse/label/null | 0.25.0 |
| this | cloudposse/label/null | 0.25.0 |

## Resources

| Name | Type |
|------|------|
| [aws_eks_pod_identity_association.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_instance_profile.host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.host_object_storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.host_extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.host_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.host_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.manager_from_cidrs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.manager_from_security_groups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster) | data source |
| [aws_iam_openid_connect_provider.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_openid_connect_provider) | data source |
| [aws_iam_policy_document.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.controller_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.host_object_storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.host_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| additional\_tag\_map | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| attributes | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| cluster\_api\_ingress\_enabled | Allow agent hosts to reach the cluster's Kubernetes API (port 443 on the cluster security group). Hosts read their<br/>configuration through it at boot. | `bool` | `true` | no |
| cluster\_name | Name of the EKS cluster the Tembo install runs in. | `string` | n/a | yes |
| context | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| create\_host\_role | Create the agent host IAM role and instance profile. When false, set `host_instance_profile_name` and `host_role_arn`. | `bool` | `true` | no |
| create\_security\_group | Create the host security group. When false, set `security_group_ids`. | `bool` | `true` | no |
| delimiter | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| descriptor\_formats | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>   format = string<br/>   labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| enabled | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| environment | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| host\_access\_rules | Ingress rules added to existing security groups so agent hosts can reach them, such as RDS (5432), ElastiCache (6379)<br/>or an internal load balancer. | <pre>list(object({<br/>    security_group_id = string<br/>    port              = number<br/>    description       = string<br/>  }))</pre> | `[]` | no |
| host\_instance\_profile\_name | Existing instance profile for agent hosts, when `create_host_role` is false. | `string` | `null` | no |
| host\_object\_storage\_bucket\_arns | S3 buckets agent hosts read and write session snapshots in, when they use instance-profile credentials. | `list(string)` | `[]` | no |
| host\_policy\_arns | Additional managed policies for the host role. | `list(string)` | `[]` | no |
| host\_role\_arn | Role of the existing instance profile, when `create_host_role` is false. The controller may pass only this role. | `string` | `null` | no |
| host\_ssm\_enabled | Attach `AmazonSSMManagedInstanceCore` to the host role, for access through Session Manager. | `bool` | `true` | no |
| host\_subnet\_ids | Subnets agent hosts launch into. Set this or `host_subnet_tags`. | `list(string)` | `[]` | no |
| host\_subnet\_tags | Tags selecting the subnets agent hosts launch into, such as an existing `karpenter.sh/discovery` tag. Set this or<br/>`host_subnet_ids`. The module does not tag subnets. | `map(string)` | `{}` | no |
| id\_length\_limit | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| identity\_type | How the host controller gets its IAM role: `pod_identity` (EKS Pod Identity, the default) or `irsa` (IAM roles for<br/>service accounts). Pod Identity needs the EKS Pod Identity agent, which EKS Auto Mode includes. | `string` | `"pod_identity"` | no |
| image\_parameter\_arn | SSM parameter publishing the agent host image ID, shared by Tembo. The controller may read only this parameter. | `string` | `null` | no |
| instance\_types | Instance types for the default host class in `helm_values`, in order of preference. They must provide /dev/kvm. | `list(string)` | <pre>[<br/>  "m8i.4xlarge"<br/>]</pre> | no |
| kubernetes\_namespace | Kubernetes namespace of the Tembo install (the tembo Helm release). | `string` | n/a | yes |
| label\_key\_case | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| label\_order | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| label\_value\_case | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| labels\_as\_tags | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| manager\_ingress\_cidr\_blocks | CIDR blocks allowed to reach each host's manager on port 8743, in addition to the security groups. | `list(string)` | `[]` | no |
| manager\_ingress\_security\_group\_ids | Security groups allowed to reach each host's manager on port 8743: the Tembo API and host controller pods. Defaults<br/>to the cluster security group, which EKS pods and nodes use unless security groups for pods are configured. | `list(string)` | `null` | no |
| name | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| namespace | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| oidc\_provider\_arn | IAM OIDC provider for the cluster, for `identity_type = "irsa"`. Defaults to the provider for the cluster's issuer. | `string` | `null` | no |
| regex\_replace\_chars | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| release\_name | Name of the tembo Helm release, which names the host controller's service account. | `string` | `"tembo"` | no |
| security\_group\_ids | Existing security groups for agent hosts, used with or instead of the module's group. | `list(string)` | `[]` | no |
| service\_account\_name | Overrides the host controller's service account name. Defaults to the chart's: `<release_name>-host-controller` when the<br/>release name contains `tembo`, otherwise `<release_name>-tembo-host-controller`. | `string` | `null` | no |
| stage | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| tags | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| tenant | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |
| volume\_kms\_key\_arns | Customer-managed KMS keys host volumes are encrypted with. Not needed for AWS-managed keys. | `list(string)` | `[]` | no |
| vpc\_id | VPC of the host security group. Required when `create_security_group` is true. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| controller\_role\_arn | ARN of the host controller's IAM role. |
| controller\_role\_name | Name of the host controller's IAM role. |
| helm\_values | Values for the tembo Helm chart that install the host controller with this module's identity. |
| host\_class | A host class using this module's subnets, security groups, instance profile and image parameter, for the chart's<br/>`compute.hostClasses.<name>`. Host classes need the chart's CRDs, so add them in an upgrade after the first install. |
| host\_instance\_profile\_name | Instance profile agent hosts launch with. |
| host\_role\_arn | ARN of the agent host IAM role. |
| host\_security\_group\_id | ID of the host security group the module creates. |
| ownership\_tags | Tags the host controller puts on, and requires of, the instances and volumes it manages. |
| security\_group\_ids | All security groups agent hosts launch with. |
| service\_account\_name | Host controller service account the role is bound to. |
<!-- END_TF_DOCS -->

## License

[Apache 2.0](LICENSE)
