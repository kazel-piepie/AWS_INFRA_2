locals {
  secret_name = data.aws_secretsmanager_secret.rorr.name

  # Component-specific cloud-init setup snippets.
  docker_setup = <<-EOT
    dnf -y install docker
    systemctl enable --now docker
  EOT

  component_setup = {
    datacenter_collector   = local.docker_setup
    lol_data_collector     = local.docker_setup
    datacenter_live_events = local.docker_setup
    lol_live_events        = local.docker_setup
    lol_ai                 = local.docker_setup
    kafka_ui               = <<-EOT
      dnf -y install docker
      systemctl enable --now docker
      MSK_BOOTSTRAP=$(grep '^RORR_MSK_BOOTSTRAP_SERVERS=' /etc/rorr/rorr.env | cut -d= -f2-)
      docker run -d --restart always --name kafka-ui -p 8080:8080 \
        -e KAFKA_CLUSTERS_0_NAME=rorr \
        -e KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS="$MSK_BOOTSTRAP" \
        provectuslabs/kafka-ui:latest
    EOT
    main_db                = <<-EOT
      dnf -y install postgresql16-server postgresql16
      /usr/bin/postgresql-setup --initdb
      systemctl enable --now postgresql
      # TimescaleDB extension (community packages).
      dnf -y install gcc make || true
    EOT
  }
}

# Application tier instances (collectors, live events, LoL AI) in private subnets.
resource "aws_instance" "app" {
  for_each = local.app_components

  ami                    = data.aws_ami.al2023.id
  instance_type          = each.value.instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2[each.key].name

  user_data = templatefile("${path.module}/user_data/bootstrap.sh.tftpl", {
    secret_name     = local.secret_name
    region          = var.region
    component_name  = each.key
    component_setup = local.component_setup[each.key]
  })

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name      = "${local.name_prefix}-${replace(each.key, "_", "-")}"
    Component = each.key
  }
}

# Main DB (PostgreSQL + TimescaleDB) in private subnet.
resource "aws_instance" "main_db" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = local.specs.main_db
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.db.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2["main_db"].name

  user_data = templatefile("${path.module}/user_data/bootstrap.sh.tftpl", {
    secret_name     = local.secret_name
    region          = var.region
    component_name  = "main_db"
    component_setup = local.component_setup["main_db"]
  })

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = local.main_db_volume_size[var.env]
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name      = "${local.name_prefix}-main-db"
    Component = "main_db"
  }
}

# Kafka UI monitoring host in private subnet.
resource "aws_instance" "kafka_ui" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = local.specs.kafka_ui
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.kafka_ui.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2["kafka_ui"].name

  user_data = templatefile("${path.module}/user_data/bootstrap.sh.tftpl", {
    secret_name     = local.secret_name
    region          = var.region
    component_name  = "kafka_ui"
    component_setup = local.component_setup["kafka_ui"]
  })

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name      = "${local.name_prefix}-kafka-ui"
    Component = "kafka_ui"
  }
}
