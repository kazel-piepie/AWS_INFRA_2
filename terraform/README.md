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

### Backend service (ECS Fargate)

The backend runs on ECS Fargate behind a dedicated internet-facing ALB, reusing
this stack's VPC (Fargate tasks in private subnets, ALB in public subnets).

- **ECR** `ai-rorr-{env}-backend` — image repository (CI/CD builds/pushes).
- **ECS** cluster `ai-rorr-{env}-backend-cluster`, service
  `ai-rorr-{env}-backend-service`, task `ai-rorr-{env}-backend-task`
  (desired count 1). The task SG is allowed into the Main DB SG on 5432.
- **ALB** `ai-rorr-{env}-backend-alb` — **HTTPS (443) only** using the
  `*.rorr.club` ACM cert and `ELBSecurityPolicy-TLS13-1-2-2021-06` (no port 80).
  Idle timeout and target-group stickiness are both 600s (10-minute sessions).
- **CI/CD IAM user** `ai-rorr-{env}-backend-cicd` — least-privilege: read of
  only `ai/rorr-infra/{env}-*` and `ai/rorr/{env}-*`, scoped ECS deploy on the
  backend cluster/service, scoped `iam:PassRole` for the backend ECS roles, and
  ECR push/pull on the backend repo. Its access key is exposed via Terraform
  outputs (`backend_cicd_access_key_id`, `backend_cicd_secret_access_key`) for
  use as Git CI variables, and consumed by `.github/workflows/backend-deploy.yml`.

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
