# rorr.club domain identity with DKIM (Easy DKIM, RSA 2048-bit).
# Importing the identity already created out-of-band in prod; Terraform will
# manage it going forward. DKIM CNAME records must be added to the external
# DNS provider manually (tokens surfaced via outputs below).
import {
  to = aws_sesv2_email_identity.rorr_club_domain
  id = "rorr.club"
}

resource "aws_sesv2_email_identity" "rorr_club_domain" {
  email_identity = "rorr.club"

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }

  tags = {
    Name = "${local.name_prefix}-ses-domain"
  }
}

output "ses_dkim_tokens" {
  description = "DKIM CNAME record names to add to the external DNS for rorr.club"
  value = [
    for t in aws_sesv2_email_identity.rorr_club_domain.dkim_signing_attributes[0].tokens :
    "${t}._domainkey.rorr.club → ${t}.dkim.amazonses.com"
  ]
}

output "ses_domain_verified" {
  description = "Whether rorr.club domain identity is verified for sending"
  value       = aws_sesv2_email_identity.rorr_club_domain.verified_for_sending_status
}

# SES email-address identity for kazel@rorr.club.
# Auto-verified through the verified rorr.club domain identity above.
resource "aws_sesv2_email_identity" "kazel" {
  email_identity = "kazel@rorr.club"

  tags = {
    Name = "${local.name_prefix}-ses-kazel"
  }

  depends_on = [aws_sesv2_email_identity.rorr_club_domain]
}

output "ses_kazel_identity" {
  description = "SES email identity name for kazel@rorr.club"
  value       = aws_sesv2_email_identity.kazel.email_identity
}

output "ses_kazel_verified_for_sending" {
  description = "Whether the kazel@rorr.club identity is verified for sending"
  value       = aws_sesv2_email_identity.kazel.verified_for_sending_status
}

# SNS topics for SES event notifications.
# Bounce and complaint topics trigger immediate suppression-list handling in
# the backend. Delivery topic feeds CloudWatch for send-success monitoring.
import {
  to = aws_sns_topic.ses_bounce
  id = "arn:aws:sns:${local.region_id}:${local.account_id}:${local.name_prefix}-ses-bounce"
}

resource "aws_sns_topic" "ses_bounce" {
  name = "${local.name_prefix}-ses-bounce"

  tags = {
    Name = "${local.name_prefix}-ses-bounce"
    env  = var.env
  }
}

import {
  to = aws_sns_topic.ses_complaint
  id = "arn:aws:sns:${local.region_id}:${local.account_id}:${local.name_prefix}-ses-complaint"
}

resource "aws_sns_topic" "ses_complaint" {
  name = "${local.name_prefix}-ses-complaint"

  tags = {
    Name = "${local.name_prefix}-ses-complaint"
    env  = var.env
  }
}

import {
  to = aws_sns_topic.ses_delivery
  id = "arn:aws:sns:${local.region_id}:${local.account_id}:${local.name_prefix}-ses-delivery"
}

resource "aws_sns_topic" "ses_delivery" {
  name = "${local.name_prefix}-ses-delivery"

  tags = {
    Name = "${local.name_prefix}-ses-delivery"
    env  = var.env
  }
}

# SES configuration set.
# Suppresses future sends to bounced/complained addresses automatically.
# Imported from the resource created out-of-band; managed by Terraform going forward.
import {
  to = aws_sesv2_configuration_set.rorr
  id = "rorr-${var.env}"
}

resource "aws_sesv2_configuration_set" "rorr" {
  configuration_set_name = "rorr-${var.env}"

  suppression_options {
    suppressed_reasons = ["BOUNCE", "COMPLAINT"]
  }

  tags = {
    Name = "${local.name_prefix}-ses-config"
    env  = var.env
  }
}

# Event destinations: Bounce → SNS, Complaint → SNS, Delivery → SNS.
import {
  to = aws_sesv2_configuration_set_event_destination.bounce
  id = "rorr-${var.env}|bounce-sns"
}

resource "aws_sesv2_configuration_set_event_destination" "bounce" {
  configuration_set_name = aws_sesv2_configuration_set.rorr.configuration_set_name
  event_destination_name = "bounce-sns"

  event_destination {
    enabled              = true
    matching_event_types = ["BOUNCE"]

    sns_destination {
      topic_arn = aws_sns_topic.ses_bounce.arn
    }
  }
}

import {
  to = aws_sesv2_configuration_set_event_destination.complaint
  id = "rorr-${var.env}|complaint-sns"
}

resource "aws_sesv2_configuration_set_event_destination" "complaint" {
  configuration_set_name = aws_sesv2_configuration_set.rorr.configuration_set_name
  event_destination_name = "complaint-sns"

  event_destination {
    enabled              = true
    matching_event_types = ["COMPLAINT"]

    sns_destination {
      topic_arn = aws_sns_topic.ses_complaint.arn
    }
  }
}

import {
  to = aws_sesv2_configuration_set_event_destination.delivery
  id = "rorr-${var.env}|delivery-sns"
}

resource "aws_sesv2_configuration_set_event_destination" "delivery" {
  configuration_set_name = aws_sesv2_configuration_set.rorr.configuration_set_name
  event_destination_name = "delivery-sns"

  event_destination {
    enabled              = true
    matching_event_types = ["DELIVERY"]

    sns_destination {
      topic_arn = aws_sns_topic.ses_delivery.arn
    }
  }
}

output "ses_configuration_set_name" {
  description = "SES configuration set name to pass in SendEmail calls"
  value       = aws_sesv2_configuration_set.rorr.configuration_set_name
}

output "ses_bounce_topic_arn" {
  description = "SNS topic ARN for SES bounce events"
  value       = aws_sns_topic.ses_bounce.arn
}

output "ses_complaint_topic_arn" {
  description = "SNS topic ARN for SES complaint events"
  value       = aws_sns_topic.ses_complaint.arn
}
