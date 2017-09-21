# == Manifest: projects::app-graphite
#
# Graphite node
#
# === Variables:
#
# aws_region
# stackname
# aws_environment
# ssh_public_key
# instance_ami_filter_name
# graphite_1_subnet
# elb_external_certname
# elb_internal_certname
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

variable "instance_ami_filter_name" {
  type        = "string"
  description = "Name to use to find AMI images"
  default     = ""
}

variable "graphite_1_subnet" {
  type        = "string"
  description = "Name of the subnet to place the Graphite instance 1 and EBS volume"
}

variable "elb_external_certname" {
  type        = "string"
  description = "The ACM cert domain name to find the ARN of"
}

variable "elb_internal_certname" {
  type        = "string"
  description = "The ACM cert domain name to find the ARN of"
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.10.6"
}

provider "aws" {
  region  = "${var.aws_region}"
  version = "0.1.4"
}

data "aws_acm_certificate" "elb_external_cert" {
  domain   = "${var.elb_external_certname}"
  statuses = ["ISSUED"]
}

data "aws_acm_certificate" "elb_internal_cert" {
  domain   = "${var.elb_internal_certname}"
  statuses = ["ISSUED"]
}

resource "aws_elb" "graphite_external_elb" {
  name            = "${var.stackname}-graphite-external"
  subnets         = ["${data.terraform_remote_state.infra_networking.public_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_graphite_external_elb_id}"]
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

  tags = "${map("Name", "${var.stackname}-graphite-external", "Project", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "graphite")}"
}

resource "aws_route53_record" "graphite_external_service_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.external_zone_id}"
  name    = "graphite.${data.terraform_remote_state.infra_stack_dns_zones.external_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.graphite_external_elb.dns_name}"
    zone_id                = "${aws_elb.graphite_external_elb.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "grafana_external_service_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.external_zone_id}"
  name    = "grafana.${data.terraform_remote_state.infra_stack_dns_zones.external_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.graphite_external_elb.dns_name}"
    zone_id                = "${aws_elb.graphite_external_elb.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_elb" "graphite_internal_elb" {
  name            = "${var.stackname}-graphite-internal"
  subnets         = ["${data.terraform_remote_state.infra_networking.private_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_graphite_internal_elb_id}"]
  internal        = "true"

  listener {
    instance_port     = 2003
    instance_protocol = "tcp"
    lb_port           = 2003
    lb_protocol       = "tcp"
  }

  listener {
    instance_port     = 2004
    instance_protocol = "tcp"
    lb_port           = 2004
    lb_protocol       = "tcp"
  }

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

    target   = "TCP:2003"
    interval = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = "${map("Name", "${var.stackname}-graphite-internal", "Project", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "graphite")}"
}

resource "aws_route53_record" "graphite_internal_service_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.internal_zone_id}"
  name    = "graphite.${data.terraform_remote_state.infra_stack_dns_zones.internal_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.graphite_internal_elb.dns_name}"
    zone_id                = "${aws_elb.graphite_internal_elb.zone_id}"
    evaluate_target_health = true
  }
}

module "graphite-1" {
  source                        = "../../modules/aws/node_group"
  name                          = "${var.stackname}-graphite-1"
  vpc_id                        = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                  = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "graphite", "aws_hostname", "graphite-1")}"
  instance_subnet_ids           = "${matchkeys(values(data.terraform_remote_state.infra_networking.private_subnet_names_ids_map), keys(data.terraform_remote_state.infra_networking.private_subnet_names_ids_map), list(var.graphite_1_subnet))}"
  instance_security_group_ids   = ["${data.terraform_remote_state.infra_security_groups.sg_graphite_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                 = "m4.xlarge"
  create_instance_key           = true
  instance_key_name             = "${var.stackname}-graphite-1"
  instance_public_key           = "${var.ssh_public_key}"
  instance_additional_user_data = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids              = ["${aws_elb.graphite_internal_elb.id}", "${aws_elb.graphite_external_elb.id}"]
  instance_ami_filter_name      = "${var.instance_ami_filter_name}"
  root_block_device_volume_size = "20"
}

resource "aws_ebs_volume" "graphite-1" {
  availability_zone = "${lookup(data.terraform_remote_state.infra_networking.private_subnet_names_azs_map, var.graphite_1_subnet)}"
  size              = 100
  type              = "gp2"

  tags {
    Name            = "${var.stackname}-graphite-1"
    Project         = "${var.stackname}"
    aws_stackname   = "${var.stackname}"
    aws_environment = "${var.aws_environment}"
    aws_migration   = "graphite"
    aws_hostname    = "graphite-1"
  }
}

resource "aws_iam_policy" "graphite_1_iam_policy" {
  name   = "${var.stackname}-graphite-1-additional"
  path   = "/"
  policy = "${file("${path.module}/additional_policy.json")}"
}

resource "aws_iam_role_policy_attachment" "graphite_1_iam_role_policy_attachment" {
  role       = "${module.graphite-1.instance_iam_role_name}"
  policy_arn = "${aws_iam_policy.graphite_1_iam_policy.arn}"
}

# Outputs
# --------------------------------------------------------------

output "graphite_internal_service_dns_name" {
  value       = "${aws_route53_record.graphite_internal_service_record.fqdn}"
  description = "DNS name to access the Graphite internal service"
}

output "graphite_external_elb_dns_name" {
  value       = "${aws_route53_record.graphite_external_service_record.fqdn}"
  description = "DNS name to access the Graphite external service"
}
