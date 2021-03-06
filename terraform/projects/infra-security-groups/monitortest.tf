#
# == Manifest: Project: Security Groups: monitoring
#
# The monitoring host needs to be accessible on ports:
#   - 443 from the other VMs
#
# === Variables:
# stackname - string
#
# === Outputs:
# sg_monitoring_id
# sg_monitoring_elb_id

resource "aws_security_group" "monitortest" {
  name        = "${var.stackname}_monitortest_access"
  vpc_id      = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  description = "Access to the monitortest host from its ELB"

  tags {
    Name = "${var.stackname}_monitortest_access"
  }
}

resource "aws_security_group_rule" "allow_monitortest_external_elb_in" {
  type      = "ingress"
  from_port = 9090
  to_port   = 9090
  protocol  = "tcp"

  # Which security group is the rule assigned to
  security_group_id = "${aws_security_group.monitortest.id}"

  # Which security group can use this rule
  source_security_group_id = "${aws_security_group.monitortest_external_elb.id}"
}

resource "aws_security_group_rule" "allow_monitortest_external_elb_alertmanager_in" {
  type      = "ingress"
  from_port = 9093
  to_port   = 9093
  protocol  = "tcp"

  # Which security group is the rule assigned to
  security_group_id = "${aws_security_group.monitortest.id}"

  # Which security group can use this rule
  source_security_group_id = "${aws_security_group.monitortest_external_elb.id}"
}

resource "aws_security_group" "monitortest_external_elb" {
  name        = "${var.stackname}_monitortest_external_elb_access"
  vpc_id      = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  description = "Access the monitoring ELB"

  tags {
    Name = "${var.stackname}_monitortest_external_elb_access"
  }
}

resource "aws_security_group_rule" "allow_office_to_monitortest" {
  type      = "ingress"
  from_port = 443
  to_port   = 443
  protocol  = "tcp"

  security_group_id = "${aws_security_group.monitortest_external_elb.id}"
  cidr_blocks       = ["${var.office_ips}"]
}

# TODO test whether egress rules are needed on ELBs
resource "aws_security_group_rule" "allow_monitortest_external_elb_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.monitortest_external_elb.id}"
}

## MANAGEMENT RULES
resource "aws_security_group_rule" "allow_node_exporter_ingress_from_monitortest" {
  type      = "ingress"
  from_port = 9091
  to_port   = 9091
  protocol  = "tcp"

  # Which security group is the rule assigned to
  security_group_id = "${aws_security_group.management.id}"

  # Which security group can use this rule
  source_security_group_id = "${aws_security_group.monitortest.id}"
}

output "sg_monitortest_id" {
  value = "${aws_security_group.monitortest.id}"
}

output "sg_monitortest_external_elb_id" {
  value = "${aws_security_group.monitortest_external_elb.id}"
}
