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
      kafka_ui = "t3a.small"
      main_db  = "t3a.medium"
      neo4j    = "t3a.medium"
      socket   = "t3a.small"
    }
    staging = {
      kafka_ui = "t3a.small"
      main_db  = "t3a.large"
      neo4j    = "t3a.large"
      socket   = "t3a.medium"
    }
    prod = {
      kafka_ui = "t3a.medium"
      main_db  = "m6a.xlarge"
      neo4j    = "m6a.large"
      socket   = "m6a.large"
    }
  }

  # Neo4j dedicated data volume size (GiB) per environment. The graph database
  # lives on this separate EBS volume so it survives neo4j instance replacement.
  neo4j_data_volume_size = {
    develop = 500
    staging = 500
    prod    = 500
  }

  # Main DB root volume size (GiB) per environment.
  main_db_volume_size = {
    develop = 50
    staging = 100
    prod    = 500
  }

  # Main DB dedicated data volume size (GiB) per environment. PostgreSQL data
  # lives on this separate EBS volume so the database survives main_db instance
  # replacement (user_data_replace_on_change recreates the instance).
  main_db_data_volume_size = {
    develop = 20
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

  # Application EC2 components — datacenter_collector, lol_data_collector,
  # datacenter_live_events, lol_live_events, and lol_ai have been removed;
  # those workloads now run as ECS Fargate services in lol_backend_ecs.tf.
  app_components = {}
}
