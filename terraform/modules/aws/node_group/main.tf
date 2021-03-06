# == Module: aws::node_group
#
# This module creates an instance in a autoscaling group that expands
# in the subnets specified by the variable instance_subnet_ids. An ELB
# is also provisioned to access the instance. The instance AMI is Ubuntu,
# you can specify the version with the instance_ami_filter_name variable.
# The machine type can also be configured with a variable.
#
# When the variable create_service_dns_name is set to true, this module
# will create a DNS name service_dns_name in the zone_id specified pointing
# to the ELB record.
#
# Additionally, this module will create an IAM role that we can attach
# policies to in other modules.
#
# === Variables:
#
# name
# vpc_id
# default_tags
# instance_subnet_ids
# instance_security_group_ids
# instance_ami_filter_name
# instance_type
# create_instance_key
# instance_key_name
# instance_public_key
# instance_user_data
# instance_additional_user_data
# asg_desired_capacity
# asg_min_size
# asg_max_size
# root_block_device_volume_size
#
# === Outputs:
#
# instance_iam_role_id
# autoscaling_group_name
#

variable "name" {
  type        = "string"
  description = "Jumpbox resources name. Only alphanumeric characters and hyphens allowed"
}

variable "default_tags" {
  type        = "map"
  description = "Additional resource tags"
  default     = {}
}

variable "vpc_id" {
  type        = "string"
  description = "The ID of the VPC in which the jumpbox is created"
}

variable "instance_subnet_ids" {
  type        = "list"
  description = "List of subnet ids where the instance can be deployed"
}

variable "instance_security_group_ids" {
  type        = "list"
  description = "List of security group ids to attach to the ASG"
}

variable "instance_ami_filter_name" {
  type        = "string"
  description = "Name to use to find AMI images for the instance"
  default     = "ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"
}

variable "instance_type" {
  type        = "string"
  description = "Instance type"
  default     = "t2.micro"
}

variable "create_instance_key" {
  type        = "string"
  description = "Whether to create a key pair for the instance launch configuration"
  default     = false
}

variable "instance_key_name" {
  type        = "string"
  description = "Name of the instance key"
}

variable "instance_public_key" {
  type        = "string"
  description = "The jumpbox default public key material"
  default     = ""
}

variable "instance_user_data" {
  type        = "string"
  description = "User_data provisioning script (default user_data.sh in module directory)"
  default     = "user_data.sh"
}

variable "instance_additional_user_data" {
  type        = "string"
  description = "Append additional user-data script"
  default     = ""
}

variable "instance_default_policy" {
  type        = "string"
  description = "Name of the JSON file containing the default IAM role policy for the instance"
  default     = "default_policy.json"
}

variable "instance_elb_ids" {
  type        = "list"
  description = "A list of the ELB IDs to attach this ASG to"
}

variable "asg_desired_capacity" {
  type        = "string"
  description = "The autoscaling groups desired capacity"
  default     = "1"
}

variable "asg_max_size" {
  type        = "string"
  description = "The autoscaling groups max_size"
  default     = "1"
}

variable "asg_min_size" {
  type        = "string"
  description = "The autoscaling groups max_size"
  default     = "1"
}

variable "root_block_device_volume_size" {
  type        = "string"
  description = "The size of the instance root volume in gigabytes"
  default     = "20"
}

# Resources
#--------------------------------------------------------------

data "aws_ami" "node_ami_ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["${var.instance_ami_filter_name}"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_iam_role" "node_iam_role" {
  name = "${var.name}"
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "node_iam_policy_default" {
  name   = "${var.name}-default"
  path   = "/"
  policy = "${file("${path.module}/${var.instance_default_policy}")}"
}

resource "aws_iam_role_policy_attachment" "node_iam_role_policy_attachment_default" {
  role       = "${aws_iam_role.node_iam_role.name}"
  policy_arn = "${aws_iam_policy.node_iam_policy_default.arn}"
}

resource "aws_iam_instance_profile" "node_instance_profile" {
  name = "${var.name}"
  role = "${aws_iam_role.node_iam_role.name}"
}

resource "aws_key_pair" "node_key" {
  count      = "${var.create_instance_key}"
  key_name   = "${var.instance_key_name}"
  public_key = "${var.instance_public_key}"
}

resource "aws_launch_configuration" "node_launch_configuration" {
  name          = "${var.name}"
  image_id      = "${data.aws_ami.node_ami_ubuntu.id}"
  instance_type = "${var.instance_type}"
  user_data     = "${join("\n\n", list(file("${path.module}/${var.instance_user_data}"), var.instance_additional_user_data))}"

  security_groups = ["${var.instance_security_group_ids}"]

  iam_instance_profile        = "${aws_iam_instance_profile.node_instance_profile.name}"
  associate_public_ip_address = false
  key_name                    = "${var.instance_key_name}"

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "${var.root_block_device_volume_size}"
    delete_on_termination = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "null_resource" "node_autoscaling_group_tags" {
  count = "${length(keys(var.default_tags))}"

  triggers {
    key                 = "${element(keys(var.default_tags), count.index)}"
    value               = "${element(values(var.default_tags), count.index)}"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "node_autoscaling_group" {
  name = "${var.name}"

  vpc_zone_identifier = [
    "${var.instance_subnet_ids}",
  ]

  desired_capacity          = "${var.asg_desired_capacity}"
  min_size                  = "${var.asg_min_size}"
  max_size                  = "${var.asg_max_size}"
  health_check_grace_period = "60"
  health_check_type         = "EC2"
  force_delete              = false
  wait_for_capacity_timeout = 0
  launch_configuration      = "${aws_launch_configuration.node_launch_configuration.name}"
  load_balancers            = ["${var.instance_elb_ids}"]

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  tags = ["${concat(
    list(map("key", "Name", "value", "${var.name}", "propagate_at_launch", true)),
    null_resource.node_autoscaling_group_tags.*.triggers)
  }"]

  lifecycle {
    create_before_destroy = true
  }
}

# Outputs
#--------------------------------------------------------------

output "instance_iam_role_name" {
  value       = "${aws_iam_role.node_iam_role.name}"
  description = "Node IAM Role Name. Use with aws_iam_role_policy_attachment to attach specific policies to the node role"
}

output "autoscaling_group_name" {
  value       = "${aws_autoscaling_group.node_autoscaling_group.name}"
  description = "The name of the node auto scaling group."
}
