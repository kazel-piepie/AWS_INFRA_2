# Backend service outputs.

output "backend_alb_dns_name" {
  description = "Backend ALB DNS name (point a rorr.club record at this)"
  value       = aws_lb.backend.dns_name
}

output "backend_alb_zone_id" {
  description = "Backend ALB hosted zone id (for Route53 alias records)"
  value       = aws_lb.backend.zone_id
}

output "backend_ecr_repository_url" {
  description = "ECR repository URL for the backend image"
  value       = aws_ecr_repository.backend.repository_url
}
