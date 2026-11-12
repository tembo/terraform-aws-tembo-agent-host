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

  # The install's URL, for file uploads to the object storage bucket.
  object_storage_cors_allowed_origins = ["https://tembo.example.com"]

  # Let hosts reach the database and Redis.
  host_access_rules = [
    { security_group_id = "sg-0123456789abcdef0", port = 5432, description = "Postgres from Tembo agent hosts" },
    { security_group_id = "sg-0123456789abcdef1", port = 6379, description = "Redis from Tembo agent hosts" },
  ]

  namespace = "acme"
  name      = "tembo"
}
```

Pass `helm_values` to the `tembo` chart, before your own values so they can override it:

```hcl
resource "helm_release" "tembo" {
  name      = "tembo"
  namespace = "tembo"
  chart     = "tembo-x.y.z.tgz" # The tembo chart from your Tembo release.

  values = [
    yamlencode(module.tembo_agent_host.helm_values),
    file("values.yaml"),
  ]
}
```

`helm_values` turns on the chart's AWS settings (`provider.aws`), and installs the controller with this module's
identity, and a host class and pool named `default`: the module's subnets, security groups, instance profile, image and
`instance_types`, one to three hosts. On EKS Auto Mode it also gives the chart's internal load balancers Auto Mode's
class (`provider.aws.loadBalancerClass`). `host_class` is the same class, for adding more.

The class selects Tembo's agent host image by channel (`image_channel`, default `stable`). The host controller sends the
install's license key to Tembo's API, which shares the image with this account and grants it use of the image's KMS key;
the controller may use Tembo's keys only through EC2. Set `image_parameter_arn` to select an image yourself instead.

The release name and namespace must match `release_name` and `kubernetes_namespace`: the controller role trusts only
the chart's service account, and the controller tags instances with the namespace.

### Identity

`identity_type = "pod_identity"` (the default) creates an EKS Pod Identity association, which needs the EKS Pod Identity
agent; EKS Auto Mode includes it. `identity_type = "irsa"` trusts the cluster's IAM OIDC provider instead and adds the
role annotation to `helm_values`.

### Object storage

By default the module creates an S3 bucket for the install: project builds (VM golden snapshots), file uploads and agent
assets. Agent hosts get access through their role, and the chart's service account (the API, worker and cron) through a
control plane role, bound like the controller's. `helm_values` sets the chart's `objectStorage` values. Pass the
install's URL in `object_storage_cors_allowed_origins` so browsers can upload files.

To use an existing bucket, set `object_storage_bucket_name`; the module then manages only access to it. Set
`object_storage_enabled = false` to install without object storage, which turns off project builds and file uploads.

### Existing resources

Set `create_security_group = false` with `security_group_ids`, or `create_host_role = false` with
`host_instance_profile_name` and `host_role_arn`, to use your own. The controller role is still limited to them.

## Examples

- [`examples/complete`](examples/complete): a VPC, an EKS cluster and the module.

## Tests

The Terratest suite in [`test/src`](test/src) applies [`examples/complete`](examples/complete) in AWS:

```sh
make -C test/src test
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5 |
| aws | >= 5.79, < 7.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.79, < 7.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| control\_plane\_label | cloudposse/label/null | 0.25.0 |
| controller\_label | cloudposse/label/null | 0.25.0 |
| host\_label | cloudposse/label/null | 0.25.0 |
| storage\_label | cloudposse/label/null | 0.25.0 |
| this | cloudposse/label/null | 0.25.0 |

## Resources

| Name | Type |
|------|------|
| [aws_eks_pod_identity_association.control_plane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_instance_profile.host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.control_plane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.control_plane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.host_object_storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.host_extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.host_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_s3_bucket.storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_cors_configuration.storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_cors_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_public_access_block.storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_security_group.host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.host_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.manager_from_cidrs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.manager_from_security_groups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster) | data source |
| [aws_iam_policy_document.control_plane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.control_plane_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
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
| control\_plane\_service\_account\_name | Overrides the service account of the chart's API, worker and cron, which the object storage role is bound to. Defaults to the chart's: the release name when it contains `tembo`, otherwise `<release_name>-tembo`. | `string` | `null` | no |
| create\_host\_role | Create the agent host IAM role and instance profile. When false, set `host_instance_profile_name` and `host_role_arn`. | `bool` | `true` | no |
| create\_security\_group | Create the host security group. When false, set `security_group_ids`. | `bool` | `true` | no |
| delimiter | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| descriptor\_formats | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>   format = string<br/>   labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| enabled | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| environment | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| host\_access\_rules | Ingress rules added to existing security groups so agent hosts can reach them, such as RDS (5432), ElastiCache (6379)<br/>or an internal load balancer. | <pre>list(object({<br/>    security_group_id = string<br/>    port              = number<br/>    description       = string<br/>  }))</pre> | `[]` | no |
| host\_instance\_profile\_name | Existing instance profile for agent hosts, when `create_host_role` is false. | `string` | `null` | no |
| host\_object\_storage\_bucket\_arns | Additional S3 buckets agent hosts read and write, when they use instance-profile credentials. The install's object storage bucket is included without listing it here. | `list(string)` | `[]` | no |
| host\_policy\_arns | Additional managed policies for the host role. | `list(string)` | `[]` | no |
| host\_role\_arn | Role of the existing instance profile, when `create_host_role` is false. The controller may pass only this role. | `string` | `null` | no |
| host\_ssm\_enabled | Attach `AmazonSSMManagedInstanceCore` to the host role, for access through Session Manager. | `bool` | `true` | no |
| host\_subnet\_ids | Subnets agent hosts launch into. Set this or `host_subnet_tags`. | `list(string)` | `[]` | no |
| host\_subnet\_tags | Tags selecting the subnets agent hosts launch into, such as an existing `karpenter.sh/discovery` tag. Set this or<br/>`host_subnet_ids`. The module does not tag subnets. | `map(string)` | `{}` | no |
| id\_length\_limit | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| identity\_type | How the host controller gets its IAM role: `pod_identity` (EKS Pod Identity, the default) or `irsa` (IAM roles for<br/>service accounts). Pod Identity needs the EKS Pod Identity agent, which EKS Auto Mode includes. | `string` | `"pod_identity"` | no |
| image\_channel | Tembo agent host image channel the default host class in `helm_values` selects. The host controller gets the<br/>channel's image from Tembo's API with the install's license key, which shares it with this account. | `string` | `"stable"` | no |
| image\_parameter\_arn | SSM parameter publishing an agent host image ID, instead of `image_channel`. The controller may read only this parameter. | `string` | `null` | no |
| instance\_types | Instance types for the default host class in `helm_values`, in order of preference. They must provide /dev/kvm. | `list(string)` | <pre>[<br/>  "c8id.8xlarge"<br/>]</pre> | no |
| kubernetes\_namespace | Kubernetes namespace of the Tembo install (the tembo Helm release). | `string` | n/a | yes |
| label\_key\_case | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| label\_order | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| label\_value\_case | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| labels\_as\_tags | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| manager\_ingress\_cidr\_blocks | CIDR blocks allowed to reach each host's manager on port 8743, in addition to the security groups. | `list(string)` | `[]` | no |
| manager\_ingress\_security\_group\_ids | Security groups allowed to reach each host's manager on port 8743: the Tembo API and host controller pods. Defaults<br/>to the cluster security group, which EKS pods and nodes use unless security groups for pods are configured. | `list(string)` | `null` | no |
| name | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| namespace | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| object\_storage\_bucket\_name | Existing S3 bucket to use instead of creating one. The module then manages only access to it; set its CORS yourself. | `string` | `null` | no |
| object\_storage\_cors\_allowed\_origins | Origins browsers upload files from, such as `https://tembo.example.com`: the install's URL. Without one, file uploads from the browser fail. | `list(string)` | `[]` | no |
| object\_storage\_enabled | Give the install object storage: an S3 bucket for project builds (VM golden snapshots), file uploads and agent<br/>assets, read and write access for agent hosts and the control plane (a role for the chart's service account), and<br/>the chart's `objectStorage` values in `helm_values`. Without it, project builds and file uploads are off. | `bool` | `true` | no |
| object\_storage\_force\_destroy | Delete the created bucket's objects when the module is destroyed. | `bool` | `false` | no |
| oidc\_provider\_arn | IAM OIDC provider for the cluster, for `identity_type = "irsa"`. Defaults to the provider named after the cluster's<br/>issuer. Pass the provider's ARN when it is created in the same apply, so the role is created after it. | `string` | `null` | no |
| regex\_replace\_chars | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| release\_name | Name of the tembo Helm release, which names the host controller's service account. | `string` | `"tembo"` | no |
| root\_volume\_initialization\_rate | Rate in MiB/s (100 to 300) at which EBS loads a new host's root volume from the image's snapshot, for the default host<br/>class. Loaded lazily instead (null), a host's first boot can outlast the controller's registration timeout. | `number` | `300` | no |
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
| control\_plane\_role\_arn | ARN of the control plane's role, which reads and writes the install's object storage. |
| controller\_role\_arn | ARN of the host controller's IAM role. |
| controller\_role\_name | Name of the host controller's IAM role. |
| helm\_values | Values for the tembo Helm chart: its AWS settings (`provider.aws`, with EKS Auto Mode's load balancer class), the<br/>host controller with this module's identity, a host class and pool named `default`, and with object storage, the<br/>bucket and the control plane's identity. |
| host\_class | A host class using this module's subnets, security groups, instance profile and image parameter, for the chart's<br/>`compute.hostClasses.<name>`. `helm_values` already sets one named `default`. |
| host\_instance\_profile\_name | Instance profile agent hosts launch with. |
| host\_role\_arn | ARN of the agent host IAM role. |
| host\_security\_group\_id | ID of the host security group the module creates. |
| object\_storage\_bucket\_arn | ARN of the install's object storage bucket. |
| object\_storage\_bucket\_name | The install's object storage bucket. |
| ownership\_tags | Tags the host controller puts on, and requires of, the instances and volumes it manages. |
| security\_group\_ids | All security groups agent hosts launch with. |
| service\_account\_name | Host controller service account the role is bound to. |
<!-- END_TF_DOCS -->

## License

[Apache 2.0](LICENSE)
