# == Manifest: projects::app-puppetmaster
#
# Deploy node
#
# === Variables:
#
# aws_region
# stackname
# aws_environment
# ssh_public_key
# instance_ami_filter_name
# elb_external_certname
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

variable "elb_external_certname" {
  type        = "string"
  description = "The ACM cert domain name to find the ARN of"
}

variable "deploy_subnet" {
  type        = "string"
  description = "Name of the subnet to place the apt instance 1 and EBS volume"
}

variable "remote_state_infra_artefact_bucket_stack" {
  type        = "string"
  description = "Override infra_artefact_bucket remote state path"
  default     = ""
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.10.7"
}

# This is one of two places that should need to use this particular remote state
# so keep it in main
data "terraform_remote_state" "artefact_bucket" {
  backend = "s3"

  config {
    bucket = "${var.remote_state_bucket}"
    key    = "${coalesce(var.remote_state_infra_artefact_bucket_stack, var.stackname)}/artefact-bucket.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" {
  region  = "${var.aws_region}"
  version = "1.0.0"
}

data "aws_acm_certificate" "elb_external_cert" {
  domain   = "${var.elb_external_certname}"
  statuses = ["ISSUED"]
}

resource "aws_elb" "deploy_elb" {
  name            = "${var.stackname}-deploy"
  subnets         = ["${data.terraform_remote_state.infra_networking.public_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_deploy_elb_id}"]
  internal        = "false"

  access_logs {
    bucket        = "${data.terraform_remote_state.infra_aws_logging.aws_logging_bucket_id}"
    bucket_prefix = "${var.stackname}-deploy-external-elb"
    interval      = 60
  }

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

  tags = "${map("Name", "${var.stackname}-deploy", "Project", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "jenkins")}"
}

resource "aws_route53_record" "service_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.external_zone_id}"
  name    = "deploy.${data.terraform_remote_state.infra_stack_dns_zones.external_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.deploy_elb.dns_name}"
    zone_id                = "${aws_elb.deploy_elb.zone_id}"
    evaluate_target_health = true
  }
}

module "deploy" {
  source                        = "../../modules/aws/node_group"
  name                          = "${var.stackname}-deploy"
  vpc_id                        = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                  = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "jenkins", "aws_hostname", "jenkins-1")}"
  instance_subnet_ids           = "${matchkeys(values(data.terraform_remote_state.infra_networking.private_subnet_names_ids_map), keys(data.terraform_remote_state.infra_networking.private_subnet_names_ids_map), list(var.deploy_subnet))}"
  instance_security_group_ids   = ["${data.terraform_remote_state.infra_security_groups.sg_deploy_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                 = "t2.medium"
  create_instance_key           = true
  instance_key_name             = "${var.stackname}-deploy"
  instance_public_key           = "${var.ssh_public_key}"
  instance_additional_user_data = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids              = ["${aws_elb.deploy_elb.id}"]
  instance_ami_filter_name      = "${var.instance_ami_filter_name}"
}

resource "aws_ebs_volume" "deploy" {
  availability_zone = "${lookup(data.terraform_remote_state.infra_networking.private_subnet_names_azs_map, var.deploy_subnet)}"
  size              = 40
  type              = "gp2"

  tags {
    Name            = "${var.stackname}-deploy"
    Project         = "${var.stackname}"
    Device          = "xvdf"
    aws_hostname    = "jenkins-1"
    aws_migration   = "jenkins"
    aws_stackname   = "${var.stackname}"
    aws_environment = "${var.aws_environment}"
  }
}

resource "aws_iam_policy" "deploy_iam_policy" {
  name   = "${var.stackname}-deploy-additional"
  path   = "/"
  policy = "${file("${path.module}/additional_policy.json")}"
}

resource "aws_iam_role_policy_attachment" "deploy_iam_role_policy_attachment" {
  role       = "${module.deploy.instance_iam_role_name}"
  policy_arn = "${aws_iam_policy.deploy_iam_policy.arn}"
}

# Outputs
# --------------------------------------------------------------

output "deploy_elb_dns_name" {
  value       = "${aws_elb.deploy_elb.dns_name}"
  description = "DNS name to access the deploy service"
}
