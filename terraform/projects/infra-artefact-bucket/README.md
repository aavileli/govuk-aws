
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| aws_environment | AWS Environment | string | - | yes |
| aws_region | AWS region | string | `eu-west-1` | no |
| aws_secondary_region | Secondary region for cross-replication | string | `eu-west-2` | no |

## Outputs

| Name | Description |
|------|-------------|
| write_artefact_bucket_policy_arn | ARN of the write artefact-bucket policy |

