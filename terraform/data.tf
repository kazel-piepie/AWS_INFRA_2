# Pre-existing RORR service secret (created by MCP server prerequisite work).
# Always referenced as a data source, never created here.
data "aws_secretsmanager_secret" "rorr" {
  name = "ai/rorr/${var.env}"
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
