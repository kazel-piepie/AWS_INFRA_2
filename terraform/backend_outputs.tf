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

output "backend_ecs_cluster_name" {
  description = "Backend ECS cluster name"
  value       = aws_ecs_cluster.backend.name
}

output "backend_ecs_service_name" {
  description = "Backend ECS service name"
  value       = aws_ecs_service.backend.name
}

# --- Backend CI/CD IAM user credentials (store as Git CI variables) ---
output "backend_cicd_access_key_id" {
  description = "Access key id for the backend CI/CD IAM user"
  value       = aws_iam_access_key.backend_cicd.id
}

output "backend_cicd_secret_access_key" {
  description = "Secret access key for the backend CI/CD IAM user"
  value       = aws_iam_access_key.backend_cicd.secret
  sensitive   = true
}
