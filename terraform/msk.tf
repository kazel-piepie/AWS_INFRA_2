resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${local.name_prefix}"
  retention_in_days = 7
}

resource "aws_msk_configuration" "main" {
  name           = "${local.name_prefix}-msk-config"
  kafka_versions = ["3.6.0"]

  server_properties = <<-PROPERTIES
    auto.create.topics.enable=true
    default.replication.factor=2
    min.insync.replicas=1
    num.partitions=3
  PROPERTIES
}

resource "aws_msk_cluster" "main" {
  cluster_name           = "${local.name_prefix}-msk"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = local.msk_broker_nodes[var.env]

  broker_node_group_info {
    instance_type   = local.msk_broker_instance_type[var.env]
    client_subnets  = aws_subnet.private[*].id
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 20
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = {
    Name = "${local.name_prefix}-msk"
  }
}
