
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| aws_environment | AWS Environment | string | - | yes |
| aws_region | AWS region | string | `eu-west-1` | no |
| password | DB password | string | - | yes |
| remote_state_bucket | S3 bucket we store our terraform state in | string | - | yes |
| remote_state_infra_networking_key_stack | Override infra_networking remote state path | string | `` | no |
| remote_state_infra_security_groups_key_stack | Override infra_security_groups stackname path to infra_vpc remote state | string | `` | no |
| remote_state_infra_stack_dns_zones_key_stack | Override stackname path to infra_vpc remote state | string | `` | no |
| remote_state_infra_vpc_key_stack | Override infra_vpc remote state path | string | `` | no |
| stackname | Stackname | string | - | yes |
| username | Mysql username | string | - | yes |

## Outputs

| Name | Description |
|------|-------------|
| mysql_primary_address | Mysql instance address |
| mysql_primary_endpoint | Mysql instance endpoint |
| mysql_primary_id | Mysql instance ID |
| mysql_primary_resource_id | Mysql instance resource ID |

