# ---------------------------------------------------------------------------
# Backend API custom domain: ai-dev-api.rorr.club
#
# Problem this solves: the frontend was calling the raw ALB DNS name
# (ai-rorr-develop-backend-alb-*.us-east-1.elb.amazonaws.com) over HTTPS, which
# fails with ERR_CERT_COMMON_NAME_INVALID because the ALB serves the
# *.rorr.club certificate and that name is not covered by it. Calling a
# rorr.club subdomain instead makes the served certificate valid.
#
# TLS  — already satisfied. The backend HTTPS:443 listener (backend_alb.tf)
#        already terminates TLS with the *.rorr.club wildcard certificate
#        (data.aws_acm_certificate.rorr_club). That wildcard already covers
#        ai-dev-api.rorr.club, exactly as it covers ai-dev-app.rorr.club
#        (frontend.tf) and ai-dev-resources.rorr.club (frontend-resources.tf).
#        No new certificate and no listener change are required, so none are
#        created here. A dedicated ai-dev-api.rorr.club certificate would add
#        no value and could not be DNS-validated from this account anyway (see
#        the DNS note below).
#
# DNS  — rorr.club is NOT a Route53 hosted zone in this AWS account. As with
#        the frontend records (ai-dev-app / ai-dev-resources), the rorr.club
#        records are managed out-of-band. The alias record below is therefore
#        created only when a reachable hosted zone id is supplied via
#        var.api_domain_route53_zone_id. When that variable is empty (the
#        default, and what CI/CD uses today) no DNS resource is managed and the
#        alias must be created in whatever manages rorr.club DNS, pointing
#        ai-dev-api.rorr.club at the backend_alb_dns_name output (A/ALIAS record
#        with the backend_alb_zone_id).
# ---------------------------------------------------------------------------

locals {
  # Backend API custom domain. Mirrors the frontend convention
  # (ai-dev-app / ai-dev-resources) for the develop environment.
  backend_api_domain = "ai-dev-api.rorr.club"
}

# A-alias record ai-dev-api.rorr.club -> backend ALB. Created only when a
# rorr.club hosted zone id is provided (see var.api_domain_route53_zone_id).
resource "aws_route53_record" "backend_api" {
  count = var.api_domain_route53_zone_id != "" ? 1 : 0

  zone_id = var.api_domain_route53_zone_id
  name    = local.backend_api_domain
  type    = "A"

  alias {
    name                   = aws_lb.backend.dns_name
    zone_id                = aws_lb.backend.zone_id
    evaluate_target_health = true
  }
}
