# RORR Infrastructure (Terraform)

Terraform configuration for the RORR e-sports service. All resources use the
`ai` prefix and are deployed to **us-east-1**.

## Environments

`develop` / `staging` / `prod` map 1:1 to git branches, GitHub Environments, and
AWS accounts. Specs (instance types, volume sizes, MSK broker counts) are driven
by `var.env` via maps in `locals.tf`.

| Branch  | Environment | State bucket               |
|---------|-------------|----------------------------|
| develop | develop     | `ai-rorr-tfstate-develop`  |
| staging | staging     | `ai-rorr-tfstate-staging`  |
| prod    | prod        | `ai-rorr-tfstate-prod`     |

## Components

VPC (2 AZ, public/private subnets, single NAT), MSK (Kafka, 2 brokers on
develop), ElastiCache Redis, and EC2 hosts: Main DB (PostgreSQL + TimescaleDB),
DataCenter Collector, LOL Data Collector, DataCenter Live Events, LOL Live
Events, LoL AI (Bedrock), and Kafka UI.

## Secrets

`ai/rorr/{env}` is created out-of-band (MCP server prerequisite) and referenced
here as a `data` source — never created by this config. Each component's IAM
role is granted read access to that exact secret ARN only. EC2 hosts fetch the
secret at boot (cloud-init) into `/etc/rorr/rorr.env`.

## Deployment

`terraform apply` runs **only in CI/CD** (`.github/workflows/terraform.yml`) on
push to a protected branch — never directly. The backend bucket/key are passed
per environment via `-backend-config` at `init` time.

```bash
terraform init \
  -backend-config="bucket=ai-rorr-tfstate-develop" \
  -backend-config="key=rorr/develop/terraform.tfstate"
```
