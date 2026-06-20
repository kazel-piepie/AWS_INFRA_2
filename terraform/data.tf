# Pre-existing RORR service secret (created by MCP server prerequisite work).
# Always referenced as a data source, never created here.
data "aws_secretsmanager_secret" "rorr" {
  name = "ai/rorr/${var.env}"
}

# Account id and region of the deploying account (used to build exact ARNs
# without hardcoding the account number).
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Existing ACM certificate for the rorr.club domain (wildcard *.rorr.club also
# covers rorr.club). Imported out-of-band; referenced here, never created.
data "aws_acm_certificate" "rorr_club" {
  domain      = "*.rorr.club"
  statuses    = ["ISSUED"]
  most_recent = true
}

# Latest Amazon Linux 2023 x86_64 AMI.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
