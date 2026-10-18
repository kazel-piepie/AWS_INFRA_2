output "frontend_ecs_alb_dns" {
  description = "Frontend ECS ALB DNS name (CloudFront origin)"
  value       = aws_lb.frontend_ecs.dns_name
}

output "frontend_ecs_cloudfront_domain_name" {
  description = "Frontend ECS CloudFront domain name (Route53 CNAME target)"
  value       = aws_cloudfront_distribution.frontend_ecs.domain_name
}

output "frontend_ecs_cloudfront_distribution_id" {
  description = "Frontend ECS CloudFront distribution ID"
  value       = aws_cloudfront_distribution.frontend_ecs.id
}

output "frontend_ecs_cluster_name" {
  description = "Frontend ECS cluster name"
  value       = aws_ecs_cluster.frontend_ecs.name
}

output "frontend_ecs_service_name" {
  description = "Frontend ECS service name"
  value       = aws_ecs_service.frontend_ecs.name
}

output "frontend_ecs_ecr_repository_url" {
  description = "Frontend ECS ECR repository URL"
  value       = aws_ecr_repository.frontend_ecs.repository_url
}

output "frontend_ecs_cicd_key_secret_arn" {
  description = "ARN of the secret holding the frontend ECS CI/CD access key"
  value       = aws_secretsmanager_secret.frontend_ecs_cicd_key.arn
}
