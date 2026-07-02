# ---------------------------------------------------------------------------
# Dedicated IAM user for backend CI/CD (Git): reads a tightly-scoped set of
# secrets and deploys the backend Docker image to ECS. Least privilege only.
# ---------------------------------------------------------------------------
locals {
  account_id = data.aws_caller_identity.current.account_id
  region_id  = data.aws_region.current.name

  # Exact secret ARNs (with version suffix wildcard) the CI/CD user may read.
  backend_cicd_secret_arns = [
    "arn:aws:secretsmanager:${local.region_id}:${local.account_id}:secret:ai/rorr-infra/${var.env}-*",
    "arn:aws:secretsmanager:${local.region_id}:${local.account_id}:secret:ai/rorr/${var.env}-*",
  ]

  # ECS service ARN for the backend (scopes UpdateService / DescribeServices).
  backend_service_arn = "arn:aws:ecs:${local.region_id}:${local.account_id}:service/${aws_ecs_cluster.backend.name}/${aws_ecs_service.backend.name}"
}

resource "aws_iam_user" "backend_cicd" {
  name = "${local.name_prefix}-backend-cicd"
  path = "/cicd/"

  tags = {
    Name      = "${local.name_prefix}-backend-cicd"
    Component = "backend"
    Purpose   = "git-cicd-deploy"
  }
}

# Access key surfaced via Terraform outputs for storage as Git CI variables.
resource "aws_iam_access_key" "backend_cicd" {
  user = aws_iam_user.backend_cicd.name
}

data "aws_iam_policy_document" "backend_cicd" {
  # --- Secrets Manager: ONLY the two allowed secrets, read-only. ---
  statement {
    sid    = "ReadAllowedSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = local.backend_cicd_secret_arns
  }

  # --- ECS: update the backend service only. ---
  statement {
    sid    = "DeployBackendService"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [local.backend_service_arn]
  }

  # RegisterTaskDefinition / DescribeTaskDefinition do not support
  # resource-level permissions; they must be granted on "*".
  statement {
    sid    = "BackendTaskDefinition"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"]
  }

  # List / describe tasks, scoped to the backend cluster via condition.
  statement {
    sid    = "BackendClusterTasks"
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

  # Run a standalone backend task (one-off jobs / migrations), scoped to any
  # revision of the backend task definition and limited to the backend cluster.
  statement {
    sid       = "RunBackendStandaloneTask"
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = ["arn:aws:ecs:${local.region_id}:${local.account_id}:task-definition/${aws_ecs_task_definition.backend.family}:*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.backend.arn]
    }
  }

  # PassRole limited to the backend task execution + task roles, and only to
  # the ECS tasks service.
  statement {
    sid     = "PassBackendEcsRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.backend_task_execution.arn,
      aws_iam_role.backend_task.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # ECR auth token is account-wide (no resource-level support).
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # ECR push/pull limited to the backend repository.
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

  statement {
    sid       = "CreateBackendDeployBucket"
    effect    = "Allow"
    actions   = ["s3:CreateBucket"]
    resources = ["arn:aws:s3:::${local.name_prefix}-deploy"]
  }

  statement {
    sid    = "BackendDeployBucketObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::${local.name_prefix}-deploy/*"]
  }

  # --- EC2: describe socket instances (DescribeInstances has no resource-level support). ---
  statement {
    sid    = "EC2DescribeSocketInstances"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
    ]
    resources = ["*"]
  }

  # --- SSM Session Manager: open interactive sessions on socket EC2 instances only. ---
  statement {
    sid       = "SSMStartSessionOnSocket"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ec2:${local.region_id}:${local.account_id}:instance/*"]
    condition {
      test     = "StringLike"
      variable = "ssm:resourceTag/Name"
      values   = ["${local.name_prefix}-socket-*"]
    }
  }

  # Default session document required by Session Manager.
  statement {
    sid     = "SSMStartSessionDocument"
    effect  = "Allow"
    actions = ["ssm:StartSession"]
    resources = [
      "arn:aws:ssm:*:*:document/SSM-SessionManagerRunShell",
      "arn:aws:ssm:*:*:document/AWS-StartSSHSession",
    ]
  }

  # Terminate / resume only the caller's own sessions.
  statement {
    sid    = "SSMManageOwnSessions"
    effect = "Allow"
    actions = [
      "ssm:TerminateSession",
      "ssm:ResumeSession",
    ]
    resources = ["arn:aws:ssm:*:*:session/$${aws:username}-*"]
  }

  # Describe / health-check all sessions (read-only, no resource restriction).
  statement {
    sid    = "SSMDescribeSessions"
    effect = "Allow"
    actions = [
      "ssm:DescribeSessions",
      "ssm:GetConnectionStatus",
    ]
    resources = ["*"]
  }

  # --- SSM Run Command: execute programs on socket EC2 instances. ---
  statement {
    sid       = "SSMSendCommandToSocket"
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${local.region_id}:${local.account_id}:instance/*"]
    condition {
      test     = "StringLike"
      variable = "ssm:resourceTag/Name"
      values   = ["${local.name_prefix}-socket-*"]
    }
  }

  # Allow the shell-script run document for SendCommand.
  statement {
    sid       = "SSMSendCommandDocument"
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:*:*:document/AWS-RunShellScript"]
  }

  # Read command results and cancel in-flight commands.
  statement {
    sid    = "SSMCommandResults"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:CancelCommand",
    ]
    resources = ["*"]
  }
}

# Customer Managed Policy (max 6144 bytes) instead of an inline user policy
# (max 2048 bytes), which the SSM statements pushed over the limit.
resource "aws_iam_policy" "backend_cicd" {
  name   = "${local.name_prefix}-backend-cicd-policy"
  policy = data.aws_iam_policy_document.backend_cicd.json
}

resource "aws_iam_user_policy_attachment" "backend_cicd" {
  user       = aws_iam_user.backend_cicd.name
  policy_arn = aws_iam_policy.backend_cicd.arn
}
