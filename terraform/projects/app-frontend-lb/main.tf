# == Manifest: projects::app-frontend-lb
#
# Frontend application servers
#
# === Variables:
#
# aws_region
# stackname
# aws_environment
# ssh_public_key
# app_service_records
# elb_certname
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

variable "ssh_public_key" {
  type        = "string"
  description = "Default public key material"
}

variable "app_service_records" {
  type        = "list"
  description = "List of application service names that get traffic via this loadbalancer"
  default     = []
}

variable "elb_internal_certname" {
  type        = "string"
  description = "The ACM cert domain name to find the ARN of"
}

variable "elb_external_certname" {
  type        = "string"
  description = "The ACM cert domain name to find the ARN of"
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.9.10"
}

provider "aws" {
  region = "${var.aws_region}"
}

data "aws_acm_certificate" "elb_internal_cert" {
  domain   = "${var.elb_internal_certname}"
  statuses = ["ISSUED"]
}

data "aws_acm_certificate" "elb_external_cert" {
  domain   = "${var.elb_external_certname}"
  statuses = ["ISSUED"]
}

resource "aws_elb" "frontend-lb_elb" {
  name            = "${var.stackname}-frontend-lb"
  subnets         = ["${data.terraform_remote_state.infra_networking.private_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_frontend-lb_elb_id}"]
  internal        = "true"

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 443
    lb_protocol       = "https"

    ssl_certificate_id = "${data.aws_acm_certificate.elb_internal_cert.arn}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3

    target   = "TCP:80"
    interval = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = "${map("Name", "${var.stackname}-frontend-lb", "Project", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "frontend_lb")}"
}

resource "aws_route53_record" "frontend-lb_service_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.internal_zone_id}"
  name    = "frontend-lb.${data.terraform_remote_state.infra_stack_dns_zones.internal_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.frontend-lb_elb.dns_name}"
    zone_id                = "${aws_elb.frontend-lb_elb.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_elb" "frontend-lb_external_elb" {
  name            = "${var.stackname}-frontend-lb-external"
  subnets         = ["${data.terraform_remote_state.infra_networking.public_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_frontend-lb_external_elb_id}"]
  internal        = "false"

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 443
    lb_protocol       = "https"

    ssl_certificate_id = "${data.aws_acm_certificate.elb_external_cert.arn}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3

    target   = "TCP:80"
    interval = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = "${map("Name", "${var.stackname}-frontend-lb_external", "Project", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "frontend_lb")}"
}

resource "aws_route53_record" "frontend-lb_external_service_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.external_zone_id}"
  name    = "frontend-lb.${data.terraform_remote_state.infra_stack_dns_zones.external_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.frontend-lb_external_elb.dns_name}"
    zone_id                = "${aws_elb.frontend-lb_external_elb.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "app_service_records" {
  count   = "${length(var.app_service_records)}"
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.external_zone_id}"
  name    = "${element(var.app_service_records, count.index)}.${data.terraform_remote_state.infra_stack_dns_zones.external_domain_name}"
  type    = "CNAME"
  records = ["frontend-lb.${data.terraform_remote_state.infra_stack_dns_zones.external_domain_name}"]
  ttl     = "300"
}

module "frontend-lb" {
  source                        = "../../modules/aws/node_group"
  name                          = "${var.stackname}-frontend-lb"
  vpc_id                        = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                  = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "frontend_lb", "aws_hostname", "frontend-lb-1")}"
  instance_subnet_ids           = "${data.terraform_remote_state.infra_networking.private_subnet_ids}"
  instance_security_group_ids   = ["${data.terraform_remote_state.infra_security_groups.sg_frontend-lb_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                 = "t2.medium"
  create_instance_key           = true
  instance_key_name             = "${var.stackname}-frontend-lb"
  instance_public_key           = "${var.ssh_public_key}"
  instance_additional_user_data = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids              = ["${aws_elb.frontend-lb_elb.id}", "${aws_elb.frontend-lb_external_elb.id}"]
  asg_max_size                  = "2"
  asg_min_size                  = "2"
  asg_desired_capacity          = "2"
}

# Outputs
# --------------------------------------------------------------

output "frontend-lb_elb_dns_name" {
  value       = "${aws_elb.frontend-lb_elb.dns_name}"
  description = "DNS name to access the frontend-lb service"
}

output "service_dns_name" {
  value       = "${aws_route53_record.frontend-lb_service_record.fqdn}"
  description = "DNS name to access the service"
}

output "frontend-lb_external_elb_dns_name" {
  value       = "${aws_elb.frontend-lb_external_elb.dns_name}"
  description = "DNS name to access the frontend-lb service"
}

output "external_elb_service_dns_name" {
  value       = "${aws_route53_record.frontend-lb_external_service_record.fqdn}"
  description = "DNS name to access the service"
}
