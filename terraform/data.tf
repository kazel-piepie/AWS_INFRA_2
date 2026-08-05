# Pre-existing RORR service secret (created by MCP server prerequisite work).
# Always referenced as a data source, never created here.
data "aws_secretsmanager_secret" "rorr" {
  name = "ai/rorr/${var.env}"
}

# Account id and region of the deploying account (used to build exact secret
# ARNs for the backend CI/CD user without hardcoding the account number).
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Existing ACM certificate for the rorr.club domain (wildcard *.rorr.club also
# covers rorr.club). Imported out-of-band; referenced here, never created.
data "aws_acm_certificate" "rorr_club" {
  domain      = "*.rorr.club"
  statuses    = ["ISSUED"]
  most_recent = true
}
