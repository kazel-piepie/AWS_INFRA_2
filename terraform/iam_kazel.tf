# ---------------------------------------------------------------------------
# Dedicated IAM user "kazel" for human DB access via SSM port forwarding only.
# No direct DB credentials and no broad SSM access: kazel may open an SSM
# StartSession port-forwarding tunnel to the main_db instance and manage only
# its own sessions. Programmatic (AWS CLI) and console access are both enabled;
# the access key and console password are stored in Secrets Manager.
# ---------------------------------------------------------------------------

resource "aws_iam_user" "kazel" {
  name = "${local.name_prefix}-kazel"
  path = "/db-access/"

  tags = {
    Name      = "${local.name_prefix}-kazel"
    Component = "main_db"
    Purpose   = "ssm-port-forward-db-access"
  }
}

# Programmatic access key for the AWS CLI (used to start the SSM session).
resource "aws_iam_access_key" "kazel" {
  user = aws_iam_user.kazel.name
}

# Console login. The generated password is stored in Secrets Manager below;
# no PGP key, so the password is available as a Terraform attribute.
resource "aws_iam_user_login_profile" "kazel" {
  user                    = aws_iam_user.kazel.name
  password_length         = 20
  password_reset_required = false

  lifecycle {
    # Do not churn the password on every apply once it has been set.
    ignore_changes = [password_length, password_reset_required]
  }
}

# ---------------------------------------------------------------------------
# SSM port-forwarding-only policy.
#   - StartSession: only the main_db instance, and only the two port-forwarding
#     SSM documents.
#   - Terminate/Resume: only sessions owned by kazel (aws:username condition via
#     the session resource ARN).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "kazel_ssm_port_forward" {
  statement {
    sid     = "StartPortForwardingSession"
    effect  = "Allow"
    actions = ["ssm:StartSession"]
    resources = [
      aws_instance.main_db.arn,
      "arn:aws:ssm:${local.region_id}::document/AWS-StartPortForwardingSession",
      "arn:aws:ssm:${local.region_id}::document/AWS-StartPortForwardingSessionToRemoteHost",
    ]
  }

  # Manage only kazel's own sessions (session id is prefixed with the username).
  statement {
    sid    = "ManageOwnSessions"
    effect = "Allow"
    actions = [
      "ssm:TerminateSession",
      "ssm:ResumeSession",
    ]
    resources = [
      "arn:aws:ssm:*:${local.account_id}:session/$${aws:username}-*",
    ]
  }
}

resource "aws_iam_user_policy" "kazel_ssm_port_forward" {
  name   = "${local.name_prefix}-kazel-ssm-port-forward"
  user   = aws_iam_user.kazel.name
  policy = data.aws_iam_policy_document.kazel_ssm_port_forward.json
}

# ---------------------------------------------------------------------------
# Store kazel's credentials and DB connection target in a dedicated secret.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "kazel_key" {
  name        = "ai/rorr-infra/${var.env}-kazel-key"
  description = "Access key, console password and DB target for the kazel DB-access IAM user"

  tags = {
    Name      = "ai/rorr-infra/${var.env}-kazel-key"
    Component = "main_db"
    Purpose   = "db-access-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "kazel_key" {
  secret_id = aws_secretsmanager_secret.kazel_key.id
  secret_string = jsonencode({
    access_key_id     = aws_iam_access_key.kazel.id
    secret_access_key = aws_iam_access_key.kazel.secret
    console_password  = aws_iam_user_login_profile.kazel.password
    db_host           = aws_instance.main_db.private_ip
    db_port           = tostring(var.backend_db_port)
  })
}

# ---------------------------------------------------------------------------
# Merge a "kazel" group into the shared ai/rorr-infra/${env} secret after apply.
# Read-modify-write with jq so other top-level keys are preserved; this only
# adds/replaces the "kazel" key. Runs during apply (CI/CD context).
# ---------------------------------------------------------------------------
resource "null_resource" "kazel_secret" {
  triggers = {
    iam_user   = aws_iam_user.kazel.name
    key_secret = aws_secretsmanager_secret.kazel_key.name
    db_host    = aws_instance.main_db.private_ip
    db_port    = tostring(var.backend_db_port)
    secret_id  = data.aws_secretsmanager_secret.rorr_infra.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      GROUP=$(jq -n \
        --arg iamuser   "${aws_iam_user.kazel.name}" \
        --arg keysecret "${aws_secretsmanager_secret.kazel_key.name}" \
        --arg dbhost    "${aws_instance.main_db.private_ip}" \
        --arg dbport    "${var.backend_db_port}" \
        '{
          "kazel": {
            iam_user:    $iamuser,
            secret_name: $keysecret,
            db: {
              host: $dbhost,
              port: $dbport
            }
          }
        }')

      CURRENT=$(aws secretsmanager get-secret-value \
        --secret-id "${data.aws_secretsmanager_secret.rorr_infra.id}" \
        --region "${var.region}" \
        --query SecretString --output text --no-cli-pager)

      UPDATED=$(echo "$CURRENT" | jq --argjson group "$GROUP" '. * $group')

      aws secretsmanager put-secret-value \
        --secret-id "${data.aws_secretsmanager_secret.rorr_infra.id}" \
        --region "${var.region}" \
        --secret-string "$UPDATED" \
        --no-cli-pager
    EOT
  }

  depends_on = [
    aws_secretsmanager_secret_version.kazel_key,
  ]
}

# ---------------------------------------------------------------------------
# Outputs.
# ---------------------------------------------------------------------------
output "kazel_user_name" {
  description = "IAM user name for kazel DB access"
  value       = aws_iam_user.kazel.name
}

output "kazel_key_secret_arn" {
  description = "ARN of the secret holding kazel's access key and console password"
  value       = aws_secretsmanager_secret.kazel_key.arn
}
