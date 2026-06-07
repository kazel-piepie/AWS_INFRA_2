locals {
  name_prefix = "ai-rorr-${var.env}"

  # Two AZs (MSK provisioned requires brokers as a multiple of subnet count).
  azs = ["${var.region}a", "${var.region}b"]

  # Public subnets: one per AZ. Private subnets: one per AZ.
  public_subnet_cidrs  = [cidrsubnet(var.vpc_cidr, 8, 0), cidrsubnet(var.vpc_cidr, 8, 1)]
  private_subnet_cidrs = [cidrsubnet(var.vpc_cidr, 8, 10), cidrsubnet(var.vpc_cidr, 8, 11)]

  # Per-environment EC2 instance types (x86 processors; t3a/m6a are AMD x86).
  ec2_instance_types = {
    develop = {
      datacenter_collector   = "t3a.small"
      lol_data_collector     = "t3a.small"
      datacenter_live_events = "t3a.small"
      lol_live_events        = "t3a.small"
      lol_ai                 = "t3a.medium"
      kafka_ui               = "t3a.small"
      main_db                = "t3a.medium"
    }
    staging = {
      datacenter_collector   = "t3a.medium"
      lol_data_collector     = "t3a.medium"
      datacenter_live_events = "t3a.medium"
      lol_live_events        = "t3a.medium"
      lol_ai                 = "t3a.large"
      kafka_ui               = "t3a.small"
      main_db                = "t3a.large"
    }
    prod = {
      datacenter_collector   = "t3a.large"
      lol_data_collector     = "t3a.large"
      datacenter_live_events = "m6a.large"
      lol_live_events        = "m6a.large"
      lol_ai                 = "m6a.large"
      kafka_ui               = "t3a.medium"
      main_db                = "m6a.xlarge"
    }
  }

  # Main DB root volume size (GiB) per environment.
  main_db_volume_size = {
    develop = 50
    staging = 100
    prod    = 500
  }

  # ElastiCache Redis node type per environment.
  redis_node_type = {
    develop = "cache.t3.micro"
    staging = "cache.t3.small"
    prod    = "cache.t3.medium"
  }

  # Single-node clusters here; prod scales out via a replication group (handled
  # separately when prod is provisioned). aws_elasticache_cluster with the redis
  # engine requires num_cache_nodes = 1.
  redis_num_nodes = {
    develop = 1
    staging = 1
    prod    = 1
  }

  # MSK broker count (must be a multiple of the number of client subnets).
  msk_broker_nodes = {
    develop = 2
    staging = 2
    prod    = 4
  }

  msk_broker_instance_type = {
    develop = "kafka.t3.small"
    staging = "kafka.t3.small"
    prod    = "kafka.m5.large"
  }

  specs = local.ec2_instance_types[var.env]

  # Application EC2 components (collectors, live events, AI).
  app_components = {
    datacenter_collector   = { instance_type = local.specs.datacenter_collector, bedrock = false }
    lol_data_collector     = { instance_type = local.specs.lol_data_collector, bedrock = false }
    datacenter_live_events = { instance_type = local.specs.datacenter_live_events, bedrock = false }
    lol_live_events        = { instance_type = local.specs.lol_live_events, bedrock = false }
    lol_ai                 = { instance_type = local.specs.lol_ai, bedrock = true }
  }
}
