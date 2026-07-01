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
