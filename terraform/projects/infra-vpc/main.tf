# == Manifest: projects::infra-vpc
#
# Creates the base VPC layer for an AWS stack.
#
# === Variables:
#
# aws_region
# stackname
# vpc_name
# vpc_cidr
# traffic_type
# log_retention
#
# === Outputs:
#
# vpc_id
# vpc_cidr
# internet_gateway_id
# route_table_public_id
# flow_log_id

variable "aws_region" {
  type        = "string"
  description = "AWS region"
  default     = "eu-west-1"
}

variable "stackname" {
  type        = "string"
  description = "Stackname"
  default     = ""
}

variable "vpc_name" {
  type        = "string"
  description = "A name tag for the VPC"
}

variable "vpc_cidr" {
  type        = "string"
  description = "VPC IP address range, represented as a CIDR block"
}

variable "traffic_type" {
  type        = "string"
  description = "The traffic type to capture. Allows ACCEPT, ALL or REJECT"
  default     = "REJECT"
}

variable "log_retention" {
  type        = "string"
  description = "Number of days to retain flow logs for"
  default     = "3"
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

module "vpc" {
  source       = "../../modules/aws/network/vpc"
  name         = "${var.vpc_name}"
  cidr         = "${var.vpc_cidr}"
  default_tags = "${map("Project", var.stackname)}"
}

resource "aws_flow_log" "vpc_flow_log" {
  log_group_name = "${aws_cloudwatch_log_group.vpc_flow_log.name}"
  iam_role_arn   = "${aws_iam_role.vpc_flow_logs_role.arn}"
  vpc_id         = "${module.vpc.vpc_id}"
  traffic_type   = "${var.traffic_type}"
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "vpc_flow_logs-${var.stackname}"
  retention_in_days = "${var.log_retention}"
}

resource "aws_iam_role" "vpc_flow_logs_role" {
  name = "vpc_flow_logs_${var.stackname}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "vpc_flow_logs_policy" {
  name   = "vpc_flow_logs_policy-${var.stackname}"
  path   = "/"
  policy = "${file("${path.module}/vpc_flow_logs_policy.json")}"
}

resource "aws_iam_role_policy_attachment" "vpc_flow_logs_policy_attachment" {
  role       = "${aws_iam_role.vpc_flow_logs_role.name}"
  policy_arn = "${aws_iam_policy.vpc_flow_logs_policy.arn}"
}

# Outputs
# --------------------------------------------------------------

output "vpc_id" {
  value = "${module.vpc.vpc_id}"
}

output "vpc_cidr" {
  value = "${module.vpc.vpc_cidr}"
}

output "internet_gateway_id" {
  value = "${module.vpc.internet_gateway_id}"
}

output "route_table_public_id" {
  value = "${module.vpc.route_table_public_id}"
}

output "flow_log_id" {
  value       = "${aws_flow_log.vpc_flow_log.id}"
  description = "AWS VPC Flog log ID"
}
