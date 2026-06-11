# ---------------------------------------------------------------------------
# SES email-address identity for kazel@rorr.club.
#
# The rorr.club domain identity is already verified in SES (DKIM/domain
# verification), so addresses under that domain can already send. This adds an
# explicit email-address identity for kazel@rorr.club. On create, SES sends a
# verification email to the address unless it is auto-verified via the already
# verified parent domain.
#
# Provider default_tags (Project=ai-rorr, Environment, ManagedBy=terraform)
# apply automatically; only identity-specific tags are set here.
# ---------------------------------------------------------------------------
resource "aws_sesv2_email_identity" "kazel" {
  email_identity = "kazel@rorr.club"

  tags = {
    Name      = "${local.name_prefix}-ses-kazel"
    Component = "ses"
    Purpose   = "email-identity"
  }
}

output "ses_kazel_identity" {
  description = "SES email identity address for kazel"
  value       = aws_sesv2_email_identity.kazel.email_identity
}

output "ses_kazel_verified_for_sending" {
  description = "Whether the kazel SES email identity is verified for sending"
  value       = aws_sesv2_email_identity.kazel.verified_for_sending_status
}
