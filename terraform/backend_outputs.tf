# Backend service outputs.

output "backend_cicd_access_key_id" {
  description = "Access key id for the backend CI/CD IAM user (set as Git AWS_ACCESS_KEY_ID)"
  value       = aws_iam_access_key.backend_cicd.id
}

output "backend_cicd_secret_access_key" {
  description = "Secret access key for the backend CI/CD IAM user (set as Git AWS_SECRET_ACCESS_KEY)"
  value       = aws_iam_access_key.backend_cicd.secret
  sensitive   = true
}

output "backend_alb_dns_name" {
  description = "DNS name of the backend ALB (point a rorr.club record here)"
  value       = aws_lb.backend.dns_name
}

output "backend_alb_arn" {
  description = "ARN of the backend ALB"
  value       = aws_lb.backend.arn
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

output "backend_task_definition_family" {
  description = "Backend ECS task definition family"
  value       = aws_ecs_task_definition.backend.family
}
