variable "env" {
  description = "Deployment environment (develop, staging, prod)"
  type        = string
  default     = "develop"

  validation {
    condition     = contains(["develop", "staging", "prod"], var.env)
    error_message = "env must be one of develop, staging, prod."
  }
}

variable "region" {
  description = "AWS region (fixed to us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the RORR VPC"
  type        = string
  default     = "10.20.0.0/16"
}

# ---------------------------------------------------------------------------
# Backend service (ECS Fargate) settings.
# ---------------------------------------------------------------------------

variable "backend_container_port" {
  description = "Port the backend container listens on (target group / SG port)"
  type        = number
  default     = 8080
}

variable "backend_desired_count" {
  description = "Number of backend Fargate tasks to run"
  type        = number
  default     = 1
}

variable "backend_cpu" {
  description = "Fargate task CPU units for the backend (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "backend_memory" {
  description = "Fargate task memory (MiB) for the backend"
  type        = number
  default     = 512
}

variable "backend_health_check_path" {
  description = "ALB target group health check path for the backend"
  type        = string
  default     = "/health"
}

variable "backend_db_port" {
  description = "Database port the backend connects to (PostgreSQL = 5432)"
  type        = number
  default     = 5432
}

# Idle / session timeout for the backend ALB and sticky sessions (10 minutes).
variable "backend_session_timeout" {
  description = "ALB idle timeout and stickiness cookie duration in seconds"
  type        = number
  default     = 600
}
