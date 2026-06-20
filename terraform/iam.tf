# All EC2 components that need an instance role.
locals {
  ec2_role_components = toset(concat(
    keys(local.app_components),
    ["main_db", "kafka_ui"],
  ))
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Least-privilege read of only the ai/rorr/{env} secret (exact ARN, no wildcard).
data "aws_iam_policy_document" "rorr_secret_read" {
  statement {
    sid    = "ReadRorrSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [data.aws_secretsmanager_secret.rorr.arn]
  }
}

resource "aws_iam_policy" "rorr_secret_read" {
  name        = "${local.name_prefix}-secret-read"
  description = "Read only the ai/rorr secret for this environment"
  policy      = data.aws_iam_policy_document.rorr_secret_read.json
}

# Least-privilege write of only the ai/rorr/{env} secret (main_db only).
# main_db bootstrap generates the DB password and stores db_host/db_password.
data "aws_iam_policy_document" "rorr_secret_write" {
  statement {
    sid       = "WriteRorrSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:PutSecretValue"]
    resources = [data.aws_secretsmanager_secret.rorr.arn]
  }
}

resource "aws_iam_policy" "rorr_secret_write" {
  name        = "${local.name_prefix}-secret-write"
  description = "Write only the ai/rorr secret for this environment"
  policy      = data.aws_iam_policy_document.rorr_secret_write.json
}

resource "aws_iam_role" "ec2" {
  for_each = local.ec2_role_components

  name               = "${local.name_prefix}-${replace(each.key, "_", "-")}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name      = "${local.name_prefix}-${replace(each.key, "_", "-")}-role"
    Component = each.key
  }
}

# Every component may read the RORR secret.
resource "aws_iam_role_policy_attachment" "secret_read" {
  for_each   = local.ec2_role_components
  role       = aws_iam_role.ec2[each.key].name
  policy_arn = aws_iam_policy.rorr_secret_read.arn
}

# SSM managed access (no SSH keys / inbound 22 needed).
resource "aws_iam_role_policy_attachment" "ssm_core" {
  for_each   = local.ec2_role_components
  role       = aws_iam_role.ec2[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# PutSecretValue only for main_db (writes db_host / db_password on bootstrap).
resource "aws_iam_role_policy_attachment" "secret_write" {
  role       = aws_iam_role.ec2["main_db"].name
  policy_arn = aws_iam_policy.rorr_secret_write.arn
}

resource "aws_iam_instance_profile" "ec2" {
  for_each = local.ec2_role_components
  name     = "${local.name_prefix}-${replace(each.key, "_", "-")}-profile"
  role     = aws_iam_role.ec2[each.key].name
}
