
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| aws_region | AWS region | string | `eu-west-1` | no |
| create_external_zone | Create an external DNS zone (default true) | string | `true` | no |
| remote_state_bucket | S3 bucket we store our terraform state in | string | - | yes |
| remote_state_infra_vpc_key_stack | Override infra_vpc remote state path | string | `` | no |
| root_domain_external_name | External DNS root domain name. Override default for Integration, Staging, Production if create_external_zone is true | string | `mydomain.external` | no |
| root_domain_internal_name | Internal DNS root domain name. Override default for Integration, Staging, Production if create_internal_zone is true | string | `mydomain.internal` | no |
| stackname | Stackname | string | - | yes |

## Outputs

| Name | Description |
|------|-------------|
| external_domain_name | Route53 External Domain Name |
| external_zone_id | Route53 External Zone ID |
| internal_domain_name | Route53 Internal Domain Name |
| internal_zone_id | Outputs -------------------------------------------------------------- |

