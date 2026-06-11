# SES email-address identity for kazel@rorr.club.
#
# The parent domain identity (rorr.club) is already verified in SES with
# sending enabled, so this email-address identity is auto-verified through the
# verified domain and SES does not send a separate verification email
# (same behavior as the existing noah@rorr.club identity).
resource "aws_sesv2_email_identity" "kazel" {
  email_identity = "kazel@rorr.club"

  tags = {
    Name = "ai-rorr-ses-kazel-${var.env}"
  }
}

output "ses_kazel_identity" {
  description = "SES email identity name for kazel@rorr.club"
  value       = aws_sesv2_email_identity.kazel.email_identity
}

output "ses_kazel_verified_for_sending" {
  description = "Whether the kazel@rorr.club identity is verified for sending (true when auto-verified via the verified rorr.club domain)"
  value       = aws_sesv2_email_identity.kazel.verified_for_sending_status
}
