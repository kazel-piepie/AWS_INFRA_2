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
      # 1. TimescaleDB YUM repository
      cat > /etc/yum.repos.d/timescale_timescaledb.repo << 'REPOEOF'
      [timescale_timescaledb]
      name=timescale_timescaledb
      baseurl=https://packagecloud.io/timescale/timescaledb/el/8/$basearch
      repo_gpgcheck=1
      gpgcheck=0
      enabled=1
      gpgkey=https://packagecloud.io/timescale/timescaledb/gpgkey
      sslverify=1
      sslcacert=/etc/pki/tls/certs/ca-bundle.crt
      metadata_expire=300
      REPOEOF

      # 2. Install PostgreSQL and TimescaleDB
      dnf -y install postgresql16-server postgresql16 timescaledb-2-postgresql-16

      # 3. Init DB and configure before starting
      /usr/bin/postgresql-setup --initdb
      sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf
      echo "shared_preload_libraries = 'timescaledb'" >> /var/lib/pgsql/data/postgresql.conf
      echo "host all all 0.0.0.0/0 md5" >> /var/lib/pgsql/data/pg_hba.conf

      # 4. Start PostgreSQL
      systemctl enable --now postgresql

      # 5. Tune TimescaleDB
      timescaledb-tune --quiet --yes || true

      # 6. Generate password and create ai user + database
      DB_PASS=$(openssl rand -hex 16)
      sudo -u postgres psql -c "CREATE USER ai WITH PASSWORD '$DB_PASS';"
      sudo -u postgres psql -c "CREATE DATABASE ai OWNER ai;"
      sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ai TO ai;"
      sudo -u postgres psql -d ai -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"

      # 7. Get private DNS name via IMDSv2
      IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
      PRIVATE_DNS=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/local-hostname)

      # 8. Save db_host and db_password to Secrets Manager
      CURRENT_SECRET=$(aws secretsmanager get-secret-value --secret-id "${local.secret_name}" --region "${var.region}" --query SecretString --output text --no-cli-pager)
      UPDATED_SECRET=$(echo "$CURRENT_SECRET" | jq --arg h "$PRIVATE_DNS" --arg p "$DB_PASS" '.db_host = $h | .db_password = $p')
      aws secretsmanager put-secret-value --secret-id "${local.secret_name}" --region "${var.region}" --secret-string "$UPDATED_SECRET" --no-cli-pager
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
