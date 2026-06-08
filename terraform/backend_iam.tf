# IAM user and least-privilege policy for the backend Git CI/CD pipeline.
# This user builds/pushes the backend image to ECR and rolls out the ECS
# service. Its access key is emitted as outputs for the Git environment.

resource "aws_iam_user" "backend_cicd" {
  name = "${local.backend_name}-cicd"

  tags = {
    Name = "${local.backend_name}-cicd"
  }
}

resource "aws_iam_access_key" "backend_cicd" {
  user = aws_iam_user.backend_cicd.name
}

data "aws_iam_policy_document" "backend_cicd" {
  # Secrets Manager: read ONLY the two RORR secrets (exact ARNs, no wildcard).
  statement {
    sid    = "ReadRorrSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      data.aws_secretsmanager_secret.rorr.arn,
      data.aws_secretsmanager_secret.rorr_infra.arn,
    ]
  }

  # ECS: register/describe task definitions. These actions do not support
  # resource-level scoping in IAM, so they require "*".
  statement {
    sid    = "EcsTaskDefinitions"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"]
  }

  # ECS: deploy actions scoped to the backend service only.
  statement {
    sid    = "EcsServiceDeploy"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [local.backend_service_arn]
  }

  # ECS: list/describe tasks, constrained to the backend cluster.
  statement {
    sid    = "EcsTasks"
    effect = "Allow"
    actions = [
      "ecs:ListTasks",
      "ecs:DescribeTasks",
    ]
    resources = ["*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.backend.arn]
    }
  }

  # PassRole limited to the backend task exec/task roles, only to ECS tasks.
  statement {
    sid     = "PassBackendTaskRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.backend_task_exec.arn,
      aws_iam_role.backend_task.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # ECR: auth token is account-wide and cannot be resource-scoped.
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # ECR: push/pull restricted to the backend repository.
  statement {
    sid    = "EcrBackendRepo"
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
    resources = [aws_ecr_repository.backend.arn]
  }
}

resource "aws_iam_policy" "backend_cicd" {
  name        = "${local.backend_name}-cicd"
  description = "Least-privilege deploy policy for the RORR backend CI/CD user"
  policy      = data.aws_iam_policy_document.backend_cicd.json
}

resource "aws_iam_user_policy_attachment" "backend_cicd" {
  user       = aws_iam_user.backend_cicd.name
  policy_arn = aws_iam_policy.backend_cicd.arn
}
