# ---------------------------------------------------------------------------
# IAM user for datacenter CI/CD: reads rorr/develop/ecs-services secret and
# deploys the rorr-lol-backend image to all 8 rorr-lol-* ECS services.
# Uses long-lived access keys for CI systems that do not support WebIdentity.
# ---------------------------------------------------------------------------

resource "aws_iam_user" "datacenter_cicd" {
  name = "${local.name_prefix}-datacenter-cicd"
  path = "/cicd/"

  tags = {
    Name      = "${local.name_prefix}-datacenter-cicd"
    Component = "lol-backend"
    Purpose   = "datacenter-cicd-deploy"
  }
}

resource "aws_iam_access_key" "datacenter_cicd" {
  user = aws_iam_user.datacenter_cicd.name
}

data "aws_iam_policy_document" "datacenter_cicd" {
  # rorr/develop/ecs-services: read to resolve service names and task settings.
  statement {
    sid    = "ReadEcsServicesSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [data.aws_secretsmanager_secret.rorr_lol_ecs_services.arn]
  }

  # UpdateService / DescribeServices scoped to all rorr-lol-* services.
  statement {
    sid    = "DeployLolServices"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [local.lol_service_arn_wildcard]
  }

  # RegisterTaskDefinition / DescribeTaskDefinition / ListTaskDefinitions:
  # no resource-level permission support; must be granted on *.
  statement {
    sid    = "LolTaskDefinitions"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
    ]
    resources = ["*"]
  }

  # ListTasks / DescribeTasks scoped to the LOL backend cluster via condition.
  statement {
    sid    = "LolClusterTasks"
    effect = "Allow"
    actions = [
      "ecs:ListTasks",
      "ecs:DescribeTasks",
    ]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [local.lol_cluster_arn]
    }
  }

  # RunTask: scoped to rorr-lol-* task definition families and the LOL cluster.
  statement {
    sid     = "RunLolTask"
    effect  = "Allow"
    actions = ["ecs:RunTask"]
    resources = [
      "arn:aws:ecs:${local.region_id}:${local.account_id}:task-definition/rorr-lol-*",
    ]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [local.lol_cluster_arn]
    }
  }

  # PassRole: execution role + all 8 module task roles, ECS tasks service only.
  statement {
    sid       = "PassLolEcsRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = local.lol_passrole_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # ECR: auth token is account-wide (no resource-level support).
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # ECR: push/pull limited to the shared rorr-lol-backend repository.
  statement {
    sid    = "EcrLolBackendRepo"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [aws_ecr_repository.lol_backend.arn]
  }
}

resource "aws_iam_user_policy" "datacenter_cicd" {
  name   = "${local.name_prefix}-datacenter-cicd-policy"
  user   = aws_iam_user.datacenter_cicd.name
  policy = data.aws_iam_policy_document.datacenter_cicd.json
}
