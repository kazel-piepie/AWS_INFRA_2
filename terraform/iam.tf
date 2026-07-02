# All EC2 components that need an instance role.
locals {
  ec2_role_components = toset(concat(
    keys(local.app_components),
    ["main_db", "kafka_ui", "neo4j"],
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

# neo4j bootstrap also writes neo4j_uri / neo4j_user / neo4j_password into the
# shared ai/rorr secret, so it needs the same PutSecretValue grant as main_db.
resource "aws_iam_role_policy_attachment" "neo4j_secret_write" {
  role       = aws_iam_role.ec2["neo4j"].name
  policy_arn = aws_iam_policy.rorr_secret_write.arn
}

# Least-privilege write of only the dedicated rorr/{env}/neo4j secret. The
# neo4j bootstrap persists the live uri/username/password into it.
data "aws_iam_policy_document" "neo4j_secret_write" {
  statement {
    sid    = "WriteNeo4jSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:PutSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.neo4j.arn]
  }
}

resource "aws_iam_policy" "neo4j_secret_write" {
  name        = "${local.name_prefix}-neo4j-secret-write"
  description = "Write only the rorr neo4j secret for this environment"
  policy      = data.aws_iam_policy_document.neo4j_secret_write.json
}

resource "aws_iam_role_policy_attachment" "neo4j_dedicated_secret_write" {
  role       = aws_iam_role.ec2["neo4j"].name
  policy_arn = aws_iam_policy.neo4j_secret_write.arn
}

resource "aws_iam_instance_profile" "ec2" {
  for_each = local.ec2_role_components
  name     = "${local.name_prefix}-${replace(each.key, "_", "-")}-profile"
  role     = aws_iam_role.ec2[each.key].name
}

# MSK IAM authentication for Kafka UI.
# provectuslabs/kafka-ui connects to MSK with SASL/IAM and needs cluster
# connect, topic read/write/describe, and consumer group alter permissions.
data "aws_iam_policy_document" "kafka_ui_msk" {
  statement {
    sid    = "MSKClusterConnect"
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeCluster",
    ]
    resources = [aws_msk_cluster.main.arn]
  }

  statement {
    sid    = "MSKTopicAccess"
    effect = "Allow"
    actions = [
      "kafka-cluster:DescribeTopic",
      "kafka-cluster:DescribeTopicDynamicConfiguration",
      "kafka-cluster:ReadData",
      "kafka-cluster:WriteData",
      "kafka-cluster:CreateTopic",
      "kafka-cluster:DeleteTopic",
      "kafka-cluster:AlterTopic",
      "kafka-cluster:DeleteRecords",
    ]
    resources = ["${replace(aws_msk_cluster.main.arn, ":cluster/", ":topic/")}/*"]
  }

  statement {
    sid    = "MSKGroupAccess"
    effect = "Allow"
    actions = [
      "kafka-cluster:AlterGroup",
    ]
    resources = ["${replace(aws_msk_cluster.main.arn, ":cluster/", ":group/")}/*"]
  }
}

resource "aws_iam_role_policy" "kafka_ui_msk" {
  name   = "${local.name_prefix}-kafka-ui-msk"
  role   = aws_iam_role.ec2["kafka_ui"].id
  policy = data.aws_iam_policy_document.kafka_ui_msk.json
}
