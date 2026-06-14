# LOL backend pipeline outputs.

output "lol_backend_ecr_repository_url" {
  description = "ECR repository URL for the shared rorr-lol-backend image"
  value       = aws_ecr_repository.lol_backend.repository_url
}

output "lol_backend_service_names" {
  description = "ECS service names for the LOL backend pipeline modules"
  value       = sort(concat([for s in aws_ecs_service.lol : s.name], [aws_ecs_service.lol_collector.name]))
}

output "lol_backend_deploy_role_arn" {
  description = "GitHub OIDC deploy role ARN for the LOL backend pipeline"
  value       = aws_iam_role.lol_deploy.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}
