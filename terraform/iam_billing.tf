# ---------------------------------------------------------------------------
# Dedicated IAM user "billing" for human billing administration via the AWS
# console. Console login only (no programmatic access key): this user manages
# the Billing console end to end -- viewing costs, creating/editing budgets,
# managing payment methods, invoices, tax settings, etc. Permissions come from
# the AWS managed "Billing" job-function policy (view + manage), which covers
# billing/ce/budgets/payments/invoicing/tax/freetier/consolidatedbilling. No MFA
# is enforced by policy. The initial console password is exposed only as a
# sensitive Terraform output and is never stored in code or committed.
# ---------------------------------------------------------------------------

resource "aws_iam_user" "billing" {
  name = "${local.name_prefix}-billing"
  path = "/billing/"

  tags = {
    Name      = "${local.name_prefix}-billing"
    Component = "billing"
    Purpose   = "billing-console-administration"
  }
}

# Console login. No PGP key, so the generated password is available as a
# Terraform attribute and surfaced through a sensitive output below. The user
# must change the password on first sign-in.
resource "aws_iam_user_login_profile" "billing" {
  user                    = aws_iam_user.billing.name
  password_length         = 20
  password_reset_required = true

  lifecycle {
    # Do not churn the password on every apply once it has been set.
    ignore_changes = [password_length, password_reset_required]
  }
}

# ---------------------------------------------------------------------------
# Billing permissions. Attach the AWS managed "Billing" job-function policy,
# which grants full billing-console access (view + manage): Cost Explorer,
# Budgets, payment methods, invoices, tax settings, Free Tier, and
# consolidated billing. This managed policy was confirmed to exist at
# arn:aws:iam::aws:policy/job-function/Billing.
# ---------------------------------------------------------------------------
resource "aws_iam_user_policy_attachment" "billing" {
  user       = aws_iam_user.billing.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/Billing"
}

# ---------------------------------------------------------------------------
# Outputs. The console password is sensitive and never printed in plaintext to
# logs, code or commits; retrieve it with:
#   terraform output -raw billing_console_password
# ---------------------------------------------------------------------------
output "billing_user_name" {
  description = "IAM user name for billing console administration"
  value       = aws_iam_user.billing.name
}

output "billing_console_password" {
  description = "Initial console password for the billing IAM user (reset required on first sign-in)"
  value       = aws_iam_user_login_profile.billing.password
  sensitive   = true
}
