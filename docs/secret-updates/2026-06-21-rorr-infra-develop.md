# ai/rorr-infra/develop secret update — 2026-06-21

## Changes applied

### A. ec2_instances block
- Removed 5 terminated instances: `datacenter_collector`, `lol_data_collector`, `datacenter_live_events`, `lol_live_events`, `lol_ai`
- Updated `main_db`: instance_id=`i-0d862a2156dda4566`, private_ip=`10.20.10.98`
- Updated `kafka_ui`: instance_id=`i-09cd129acb2608693`, private_ip=`10.20.10.67`

### B. security_groups — added missing entries
- `ai-rorr-develop-backend-alb-sg`: `sg-029f1f5bf3e81b511`
- `ai-rorr-develop-backend-ecs-sg`: `sg-01729e4ef0134b71b`

### C. MSK broker addresses
- Added `msk.bootstrap_brokers_sasl_iam` (port 9098): `b-1.airorrdevelopmsk.v6bivt.c7.kafka.us-east-1.amazonaws.com:9098,b-2.airorrdevelopmsk.v6bivt.c7.kafka.us-east-1.amazonaws.com:9098`
- Cleared `msk.bootstrap_brokers` (9092) and `msk.bootstrap_brokers_tls` (9094) — IAM-only cluster, these endpoints are unreachable
- Top-level `msk_bootstrap_brokers` already empty string, unchanged

### D. ECS task definition revision
- `backend.ecs.task_definition`: updated from `:1` to `:78`

### E. ALB top-level fields
- `alb.dns`: `ai-rorr-develop-backend-alb-873660457.us-east-1.elb.amazonaws.com`
- `alb.arn`: `arn:aws:elasticloadbalancing:us-east-1:161327178737:loadbalancer/app/ai-rorr-develop-backend-alb/dab954b745deabdf`

### F. app_instance_ids
- Updated to reflect currently running instances:
  - `ai-rorr-develop-main-db`: `i-0d862a2156dda4566`
  - `ai-rorr-develop-kafka-ui`: `i-09cd129acb2608693`
