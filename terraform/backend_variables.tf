# Variables for the RORR backend service (Fargate behind a dedicated ALB).
# All backend resources are named ai-rorr-${env}-backend-*.

variable "backend_container_name" {
  description = "Container name in the backend task definition"
  type        = string
  default     = "backend"
}

variable "backend_container_port" {
  description = "Port the backend container listens on (ALB target port)"
  type        = number
  default     = 8080
}

variable "backend_task_cpu" {
  description = "Fargate task CPU units for the backend service"
  type        = number
  default     = 512
}

variable "backend_task_memory" {
  description = "Fargate task memory (MiB) for the backend service"
  type        = number
  default     = 1024
}

variable "backend_desired_count" {
  description = "Desired number of backend service tasks"
  type        = number
  default     = 1
}

variable "backend_db_port" {
  description = "Main DB (PostgreSQL + TimescaleDB) port the backend connects to"
  type        = number
  default     = 5432
}

variable "backend_cert_domain" {
  description = "ACM certificate domain to look up for the backend ALB (wildcard for rorr.club)"
  type        = string
  default     = "*.rorr.club"
}

variable "backend_health_check_path" {
  description = "Target group health check path for the backend service"
  type        = string
  default     = "/health"
}

variable "backend_image_tag" {
  description = "Container image tag deployed by CI/CD (placeholder for initial create)"
  type        = string
  default     = "latest"
}

variable "backend_session_timeout_seconds" {
  description = "Session timeout (seconds) applied to ALB idle timeout and target group stickiness"
  type        = number
  default     = 600
}
