# DataCenter CI/CD IAM user credentials. The terraform.yml workflow reads these
# after apply and stores them in the ai/service/account/develop secret under the
# aws_access_key_id / aws_secret_access_key keys.

output "datacenter_cicd_access_key_id" {
  description = "Access key id for the DataCenter CI/CD IAM user"
  value       = aws_iam_access_key.datacenter_cicd.id
}

output "datacenter_cicd_secret_access_key" {
  description = "Secret access key for the DataCenter CI/CD IAM user"
  value       = aws_iam_access_key.datacenter_cicd.secret
  sensitive   = true
}
