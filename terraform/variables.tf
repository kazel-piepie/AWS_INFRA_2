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

# Idle timeout for the backend ALB (10 minutes).
variable "backend_session_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 600
}

variable "backend_db_port" {
  description = "Database port the backend connects to (PostgreSQL = 5432)"
  type        = number
  default     = 5432
}
