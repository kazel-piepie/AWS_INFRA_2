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
secret at boot (cloud-init) into `/etc/rorr/rorr.env`. The backend Fargate task
injects the full ARNs of `ai/rorr/{env}` and `ai/rorr-infra/{env}` as
`RORR_SECRET_JSON` / `RORR_INFRA_SECRET_JSON`.

## Backend service (Fargate + ALB)

`ai-rorr-${env}-backend-*` serves the API as an ECS Fargate service behind a
dedicated internet-facing ALB:

- **ECR** `ai-rorr-${env}-backend` — image repository (push/pull by CI/CD only).
- **ECS** cluster/service/task `ai-rorr-${env}-backend-{cluster,service,task}`,
  desired count 1, tasks in private subnets, egress via the existing NAT.
- **ALB** `ai-rorr-${env}-backend-alb` — HTTPS-only (443,
  `ELBSecurityPolicy-TLS13-1-2-2021-06`), ACM `*.rorr.club` via data source;
  target group `ai-rorr-${env}-backend-tg`. ALB idle timeout and target group
  stickiness are both 600s (10-minute session timeout).
- **DB connectivity** — the backend task SG gets ingress to the existing
  `ai-rorr-${env}-db-sg` on 5432 only.
- **CI/CD user** `ai-rorr-${env}-backend-cicd` — least-privilege IAM user (ECR
  push/pull on the backend repo, ECS deploy scoped to the backend service,
  `iam:PassRole` limited to the backend task roles, and read of only
  `ai/rorr-infra/${env}` and `ai/rorr/${env}`). Its key is exposed as the
  `backend_cicd_access_key_id` / `backend_cicd_secret_access_key` (sensitive)
  outputs for the Git environment.

The reused VPC, subnets, NAT, and `ai-rorr-${env}-db-sg` are managed by this same
stack; the backend references them directly rather than creating new networking.

## Deployment

`terraform apply` runs **only in CI/CD** (`.github/workflows/terraform.yml`) on
push to a protected branch — never directly. The backend bucket/key are passed
per environment via `-backend-config` at `init` time.

```bash
terraform init \
  -backend-config="bucket=ai-rorr-tfstate-develop" \
  -backend-config="key=rorr/develop/terraform.tfstate"
```
