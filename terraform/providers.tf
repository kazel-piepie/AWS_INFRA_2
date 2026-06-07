provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "ai-rorr"
      Environment = var.env
      ManagedBy   = "terraform"
    }
  }
}
