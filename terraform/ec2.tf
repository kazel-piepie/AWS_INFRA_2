locals {
  secret_name = data.aws_secretsmanager_secret.rorr.name

  # Component-specific cloud-init setup snippets.
  component_setup = {
    kafka_ui = <<-EOT
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

      # 2. Install native PostgreSQL 16 first so /usr/bin/pg_config exists before
      #    TimescaleDB's RPM scriptlets run.
      dnf -y install postgresql16-server postgresql16

      # 2a. The el8 TimescaleDB RPM %post invokes /usr/pgsql-16/bin/pg_config (the
      #     PGDG directory layout), but AL2023's native postgresql16 package ships
      #     pg_config at /usr/bin/pg_config. Without that path the %post scriptlet
      #     cannot find pg_config and the install fails. Create the expected path
      #     as a symlink before installing TimescaleDB (skip if already present).
      if [ ! -e /usr/pgsql-16/bin/pg_config ]; then
        mkdir -p /usr/pgsql-16/bin
        ln -sf /usr/bin/pg_config /usr/pgsql-16/bin/pg_config
      fi

      # 2b. Install TimescaleDB now that pg_config is discoverable.
      dnf -y install timescaledb-2-postgresql-16

      # 2c. Make TimescaleDB libraries discoverable by the Amazon Linux native
      # postgresql16 build. The el8 TimescaleDB RPMs install the loader and
      # versioned libraries under /usr/lib64/timescaledb-*-pg16, not the native
      # postgres library dir (/usr/lib64/pgsql). Without this, postgres cannot
      # resolve the 'timescaledb' preload library and dies at startup with
      # FATAL: could not access file "timescaledb". Symlink them in before start.
      PG_LIBDIR=/usr/lib64/pgsql
      ln -sf /usr/lib64/timescaledb-loader-pg16/timescaledb.so "$PG_LIBDIR/timescaledb.so"
      for so in /usr/lib64/timescaledb-pg16/*.so; do ln -sf "$so" "$PG_LIBDIR/"; done

      # 3. Mount the dedicated EBS data volume at /var/lib/pgsql (the postgres
      #    home), NOT directly at the data directory. A fresh ext4 filesystem
      #    contains a lost+found at its root; mounting it on the data dir would
      #    place lost+found *inside* PGDATA and make initdb refuse to run with
      #    "directory not empty". Mounting one level up keeps lost+found at
      #    /var/lib/pgsql/lost+found, separate from the PGDATA subdirectory
      #    /var/lib/pgsql/data. PGDATA stays the AL2023 native default, so the
      #    stock postgresql systemd unit needs no override.
      #    The volume is attached as /dev/xvdf but surfaces as an NVMe device on
      #    Nitro instances, so resolve the real device node before using it.
      PG_MOUNT_DIR=/var/lib/pgsql
      PG_DATA_DIR=$PG_MOUNT_DIR/data
      DATA_DEV=""
      for attempt in $(seq 1 30); do
        for cand in /dev/xvdf /dev/sdf; do
          if [ -b "$cand" ]; then DATA_DEV=$(readlink -f "$cand"); break; fi
        done
        if [ -z "$DATA_DEV" ]; then
          for nvme in /dev/nvme*n1; do
            [ -b "$nvme" ] || continue
            if ebsnvme-id "$nvme" 2>/dev/null | grep -qE 'xvdf|sdf'; then DATA_DEV="$nvme"; break; fi
          done
        fi
        [ -n "$DATA_DEV" ] && break
        sleep 5
      done
      test -n "$DATA_DEV"

      # 3a. Format only if the volume has no filesystem yet (preserve any data
      #     already written by a previous instance).
      if ! blkid "$DATA_DEV" >/dev/null 2>&1; then
        mkfs.ext4 -L pgdata "$DATA_DEV"
      fi

      # 3b. Mount the volume at $PG_MOUNT_DIR and persist in fstab by UUID (nofail
      #     so a missing volume does not block boot). Then create the PGDATA
      #     subdirectory, which PostgreSQL requires to be owned by postgres and
      #     mode 0700. lost+found stays at $PG_MOUNT_DIR/lost+found, outside PGDATA.
      mkdir -p "$PG_MOUNT_DIR"
      DATA_UUID=$(blkid -s UUID -o value "$DATA_DEV")
      if ! grep -q "$DATA_UUID" /etc/fstab; then
        echo "UUID=$DATA_UUID $PG_MOUNT_DIR ext4 defaults,nofail 0 2" >> /etc/fstab
      fi
      mountpoint -q "$PG_MOUNT_DIR" || mount "$PG_MOUNT_DIR"
      chown postgres:postgres "$PG_MOUNT_DIR"
      mkdir -p "$PG_DATA_DIR"
      chown postgres:postgres "$PG_DATA_DIR"
      chmod 700 "$PG_DATA_DIR"

      # 4. Initialize the cluster only on a fresh volume (no PG_VERSION yet) so an
      #    existing database is preserved across instance replacement.
      if [ ! -f "$PG_DATA_DIR/PG_VERSION" ]; then
        /usr/bin/postgresql-setup --initdb
        sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_DATA_DIR/postgresql.conf"
        echo "shared_preload_libraries = 'timescaledb'" >> "$PG_DATA_DIR/postgresql.conf"
        echo "host all all 0.0.0.0/0 md5" >> "$PG_DATA_DIR/pg_hba.conf"
        # Tune TimescaleDB before first start so settings take effect on boot.
        timescaledb-tune --quiet --yes --conf-path "$PG_DATA_DIR/postgresql.conf" || true
      fi

      # 4a. Loopback connections must use password auth (scram-sha-256); AL2023
      #     ships them as ident, which blocks password logins. Idempotent.
      sed -ri 's#^(host[[:space:]]+all[[:space:]]+all[[:space:]]+127\.0\.0\.1/32[[:space:]]+)ident#\1scram-sha-256#' "$PG_DATA_DIR/pg_hba.conf"
      sed -ri 's#^(host[[:space:]]+all[[:space:]]+all[[:space:]]+::1/128[[:space:]]+)ident#\1scram-sha-256#' "$PG_DATA_DIR/pg_hba.conf"

      # 5. Start PostgreSQL
      systemctl enable --now postgresql

      # 6. Resolve the DB password from Secrets Manager so every (re)created
      #    instance uses the same credential. Generate one only if absent.
      SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "${local.secret_name}" --region "${var.region}" --query SecretString --output text --no-cli-pager)
      DB_PASS=$(echo "$SECRET_JSON" | jq -r '.db_password // empty')
      if [ -z "$DB_PASS" ]; then
        DB_PASS=$(openssl rand -hex 16)
      fi

      # 6a. Create or align the ai role with the secret password, then ensure the
      #     database and extension exist (idempotent for re-attached volumes).
      if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='ai'" | grep -q 1; then
        sudo -u postgres psql -c "ALTER ROLE ai WITH LOGIN PASSWORD '$DB_PASS';"
      else
        sudo -u postgres psql -c "CREATE ROLE ai WITH LOGIN PASSWORD '$DB_PASS';"
      fi
      if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='ai'" | grep -q 1; then
        sudo -u postgres psql -c "CREATE DATABASE ai OWNER ai;"
      fi
      sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ai TO ai;"
      sudo -u postgres psql -d ai -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"

      # 6a-1. Elevate the ai application role and grant it full object privileges
      #       on the public schema of every existing application database.
      #       Scope is deliberately limited: grant CREATEDB only, and explicitly
      #       deny CREATEROLE and SUPERUSER (no user-creation, no superuser).
      #       Object grants are issued WITHOUT GRANT OPTION (ai cannot re-grant).
      #       Idempotent: re-running ALTER ROLE / GRANT is a no-op, and each
      #       database is touched only if it already exists, so this is safe on
      #       re-attached data volumes and fresh instances alike.
      sudo -u postgres psql -c "ALTER ROLE ai WITH CREATEDB NOCREATEROLE NOSUPERUSER;"

      # 6a-1b. Create the rorr_app application role if it does not yet exist.
      #        rorr_app is a non-login role used by application services.
      #        Idempotent: no-op if the role already exists.
      if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='rorr_app'" | grep -q 1; then
        sudo -u postgres psql -c "CREATE ROLE rorr_app NOLOGIN NOCREATEROLE NOSUPERUSER;"
      fi

      for DB_NAME in ai test; do
        if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
          sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO ai;"
          sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO ai;"
          sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ai;"
          sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ai;"
          sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ai;"
          sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ai;"
          sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ai;"
          sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ai;"
          sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rorr_app;"
          sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO rorr_app;"
          sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO rorr_app;"
        fi
      done

      # 6a-2. Grant DEFAULT PRIVILEGES for rorr_app on rorr_datacenter and
      #        rorr_service databases. rorr_app is a non-login role (created by
      #        the bootstrap step that initialises the ai/test databases).
      #        Idempotent: ALTER DEFAULT PRIVILEGES is a no-op when re-run.
      for DB_NAME in rorr_datacenter rorr_service; do
        if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
          sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rorr_app;"
          sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO rorr_app;"
          sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO rorr_app;"
        fi
      done

      # 6a-3. Log the resulting ai role attributes so the grant can be verified
      #       from the cloud-init / bootstrap output after provisioning.
      sudo -u postgres psql -c "SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit FROM pg_roles WHERE rolname='ai';"

      # 7. Get the instance private IP via IMDSv2.
      IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
      PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

      # 8. Persist db_host (this instance IP) and db_password back to the secret.
      CURRENT_SECRET=$(aws secretsmanager get-secret-value --secret-id "${local.secret_name}" --region "${var.region}" --query SecretString --output text --no-cli-pager)
      UPDATED_SECRET=$(echo "$CURRENT_SECRET" | jq --arg h "$PRIVATE_IP" --arg p "$DB_PASS" '.db_host = $h | .db_password = $p')
      aws secretsmanager put-secret-value --secret-id "${local.secret_name}" --region "${var.region}" --secret-string "$UPDATED_SECRET" --no-cli-pager
    EOT
  }
}

# Main DB (PostgreSQL + TimescaleDB) in private subnet.
# AMI is pinned to prevent unintended instance replacement when Amazon releases
# a new AL2023 build. Update this value deliberately when upgrading the OS.
# Current: al2023-ami-2023.12.20260611.0-kernel-6.1-x86_64
resource "aws_instance" "main_db" {
  ami                    = "ami-0521cb2d60cfbb1a6"
  instance_type          = local.specs.main_db
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.db.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2["main_db"].name

  # Force instance replacement when user_data changes so a new bootstrap runs.
  user_data_replace_on_change = true

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

# Dedicated EBS data volume for PostgreSQL, separate from the root volume so the
# database survives main_db instance replacement (user_data_replace_on_change).
# prevent_destroy guards the data against accidental terraform destroy/replace.
resource "aws_ebs_volume" "main_db_data" {
  availability_zone = aws_subnet.private[0].availability_zone
  size              = local.main_db_data_volume_size[var.env]
  type              = "gp3"
  encrypted         = true

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "${local.name_prefix}-main-db-data"
    Component = "main_db"
  }
}

# Attach the data volume to main_db. force_detach lets a replaced instance
# release the volume cleanly so the new instance can re-attach and re-mount it.
resource "aws_volume_attachment" "main_db_data" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.main_db_data.id
  instance_id  = aws_instance.main_db.id
  force_detach = true
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
