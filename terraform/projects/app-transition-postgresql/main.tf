# == Manifest: projects::app-transition-postgresql
#
# RDS Transition PostgreSQL Primary instance
#
# === Variables:
#
# aws_region
# stackname
# aws_environment
# username
# password
#
# === Outputs:
#

variable "aws_region" {
  type        = "string"
  description = "AWS region"
  default     = "eu-west-1"
}

variable "stackname" {
  type        = "string"
  description = "Stackname"
}

variable "aws_environment" {
  type        = "string"
  description = "AWS Environment"
}

variable "username" {
  type        = "string"
  description = "PostgreSQL username"
}

variable "password" {
  type        = "string"
  description = "DB password"
}

variable "multi_az" {
  type        = "string"
  description = "Enable multi-az."
  default     = false
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.9.10"
}

provider "aws" {
  region  = "${var.aws_region}"
  version = "0.1.4"
}

module "transition-postgresql-primary_rds_instance" {
  source = "../../modules/aws/rds_instance"

  name               = "${var.stackname}-transition-postgresql-primary"
  engine_name        = "postgres"
  engine_version     = "9.3.14"
  default_tags       = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "transition_postgresql_primary")}"
  subnet_ids         = "${data.terraform_remote_state.infra_networking.private_subnet_rds_ids}"
  username           = "${var.username}"
  password           = "${var.password}"
  allocated_storage  = "120"
  instance_class     = "db.m4.large"
  multi_az           = "${var.multi_az}"
  security_group_ids = ["${data.terraform_remote_state.infra_security_groups.sg_transition-postgresql-primary_id}"]
}

resource "aws_route53_record" "service_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.internal_zone_id}"
  name    = "transition-postgresql-primary.${data.terraform_remote_state.infra_stack_dns_zones.internal_domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["${module.transition-postgresql-primary_rds_instance.rds_instance_address}"]
}

# Outputs
# --------------------------------------------------------------

output "transition-postgresql-primary_id" {
  value       = "${module.transition-postgresql-primary_rds_instance.rds_instance_id}"
  description = "transition-postgresql instance ID"
}

output "transition-postgresql-primary_resource_id" {
  value       = "${module.transition-postgresql-primary_rds_instance.rds_instance_resource_id}"
  description = "transition-postgresql instance resource ID"
}

output "transition-postgresql-primary_endpoint" {
  value       = "${module.transition-postgresql-primary_rds_instance.rds_instance_endpoint}"
  description = "transition-postgresql instance endpoint"
}

output "transition-postgresql-primary_address" {
  value       = "${module.transition-postgresql-primary_rds_instance.rds_instance_address}"
  description = "transition-postgresql instance address"
}
