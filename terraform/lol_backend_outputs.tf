# LOL backend pipeline outputs.

# --- Datacenter CI/CD IAM user credentials (store as CI/CD variables) ---
output "datacenter_cicd_access_key_id" {
  description = "Access key id for the datacenter CI/CD IAM user"
  value       = aws_iam_access_key.datacenter_cicd.id
}

output "datacenter_cicd_secret_access_key" {
  description = "Secret access key for the datacenter CI/CD IAM user"
  value       = aws_iam_access_key.datacenter_cicd.secret
  sensitive   = true
}

output "lol_backend_ecr_repository_url" {
  description = "ECR repository URL for the shared rorr-lol-backend image"
  value       = aws_ecr_repository.lol_backend.repository_url
}

output "lol_backend_service_names" {
  description = "ECS service names for the LOL backend pipeline modules"
  value       = sort([for s in aws_ecs_service.lol : s.name])
}

output "lol_backend_deploy_role_arn" {
  description = "GitHub OIDC deploy role ARN for the LOL backend pipeline"
  value       = aws_iam_role.lol_deploy.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}
