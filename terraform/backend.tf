# Partial backend configuration.
# Bucket and key are supplied per environment by CI/CD via -backend-config:
#   terraform init \
#     -backend-config="bucket=ai-rorr-tfstate-${ENV}" \
#     -backend-config="key=rorr/${ENV}/terraform.tfstate"
# develop backend bucket: ai-rorr-tfstate-develop
terraform {
  backend "s3" {
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
