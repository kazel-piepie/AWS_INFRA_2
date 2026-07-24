resource "aws_iam_role" "socket" {
  name               = "${local.name_prefix}-socket-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name      = "${local.name_prefix}-socket-role"
    Component = "socket"
  }
}

resource "aws_iam_instance_profile" "socket" {
  name = "${local.name_prefix}-socket-profile"
  role = aws_iam_role.socket.name
}

resource "aws_iam_role_policy_attachment" "socket_ssm" {
  role       = aws_iam_role.socket.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "socket_cloudwatch" {
  role       = aws_iam_role.socket.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

data "aws_iam_policy_document" "socket_secret_read" {
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

resource "aws_iam_role_policy" "socket_secret_read" {
  name   = "${local.name_prefix}-socket-secret-read"
  role   = aws_iam_role.socket.id
  policy = data.aws_iam_policy_document.socket_secret_read.json
}

resource "aws_iam_role_policy" "socket_s3_deploy" {
  name = "${local.name_prefix}-socket-s3-deploy"
  role = aws_iam_role.socket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DeployBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::${local.name_prefix}-deploy"]
      },
      {
        Sid    = "DeployBucketObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = ["arn:aws:s3:::${local.name_prefix}-deploy/*"]
      }
    ]
  })
}
