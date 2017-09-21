terraform {
  backend          "s3"             {}
  required_version = "= 0.10.6"
}

provider "aws" {
  region  = "${var.aws_region}"
  version = "0.1.4"
}

# used by the fastly ip ranges provider.
# an API key is needed but 'fake' seems to work.
provider "fastly" {
  api_key = "fake"
  version = "0.1.2"
}

data "fastly_ip_ranges" "fastly" {}

data "terraform_remote_state" "infra_vpc" {
  backend = "s3"

  config {
    bucket = "${var.remote_state_bucket}"
    key    = "${coalesce(var.remote_state_infra_vpc_key_stack, var.stackname)}/infra-vpc.tfstate"
    region = "eu-west-1"
  }
}
