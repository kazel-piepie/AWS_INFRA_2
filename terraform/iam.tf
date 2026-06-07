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

# Bedrock invoke for LoL AI (Sonnet model inference).
data "aws_iam_policy_document" "bedrock_invoke" {
  statement {
    sid    = "InvokeBedrock"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "bedrock_invoke" {
  name        = "${local.name_prefix}-bedrock-invoke"
  description = "Invoke Bedrock models for LoL AI"
  policy      = data.aws_iam_policy_document.bedrock_invoke.json
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

# Bedrock only for LoL AI.
resource "aws_iam_role_policy_attachment" "bedrock" {
  role       = aws_iam_role.ec2["lol_ai"].name
  policy_arn = aws_iam_policy.bedrock_invoke.arn
}

resource "aws_iam_instance_profile" "ec2" {
  for_each = local.ec2_role_components
  name     = "${local.name_prefix}-${replace(each.key, "_", "-")}-profile"
  role     = aws_iam_role.ec2[each.key].name
}
