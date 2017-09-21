# == Manifest: projects::app-mirrorer
#
# Frontend application servers
#
# === Variables:
#
# aws_region
# stackname
# aws_environment
# ssh_public_key
# instance_ami_filter_name
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
  description = "mirrorer default public key material"
}

variable "instance_ami_filter_name" {
  type        = "string"
  description = "Name to use to find AMI images"
  default     = ""
}

variable "mirrorer_subnet" {
  type        = "string"
  description = "Subnet to contain mirrorer and its EBS volume"
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.10.6"
}

provider "aws" {
  region = "${var.aws_region}"
}

module "mirrorer" {
  source                        = "../../modules/aws/node_group"
  name                          = "${var.stackname}-mirrorer"
  vpc_id                        = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                  = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "mirrorer", "aws_hostname", "mirrorer-1")}"
  instance_subnet_ids           = "${matchkeys(values(data.terraform_remote_state.infra_networking.private_subnet_names_ids_map), keys(data.terraform_remote_state.infra_networking.private_subnet_names_ids_map), list(var.mirrorer_subnet))}"
  instance_security_group_ids   = ["${data.terraform_remote_state.infra_security_groups.sg_mirrorer_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                 = "t2.micro"
  create_instance_key           = true
  instance_key_name             = "${var.stackname}-mirrorer"
  instance_public_key           = "${var.ssh_public_key}"
  instance_additional_user_data = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids              = []
  instance_ami_filter_name      = "${var.instance_ami_filter_name}"
  asg_max_size                  = "1"
  asg_min_size                  = "1"
  asg_desired_capacity          = "1"
  root_block_device_volume_size = "30"
}

resource "aws_ebs_volume" "mirrorer" {
  availability_zone = "${lookup(data.terraform_remote_state.infra_networking.private_subnet_names_azs_map, var.mirrorer_subnet)}"
  size              = 100
  type              = "gp2"

  tags {
    Name            = "${var.stackname}-mirrorer"
    Project         = "${var.stackname}"
    Device          = "xvdf"
    aws_hostname    = "mirrorer-1"
    aws_migration   = "mirrorer"
    aws_stackname   = "${var.stackname}"
    aws_environment = "${var.aws_environment}"
  }
}

resource "aws_iam_policy" "mirrorer_iam_policy" {
  name   = "${var.stackname}-mirrorer-additional"
  path   = "/"
  policy = "${file("${path.module}/additional_policy.json")}"
}

resource "aws_iam_role_policy_attachment" "mirrorer_iam_role_policy_attachment" {
  role       = "${module.mirrorer.instance_iam_role_name}"
  policy_arn = "${aws_iam_policy.mirrorer_iam_policy.arn}"
}

# Outputs
# --------------------------------------------------------------

