resource "null_resource" "main_db_timescaledb" {
  triggers = {
    timescaledb_version = "2-postgresql-16-ctrl2"
  }

  provisioner "local-exec" {
    command = <<-EOC
      SCRIPT_FILE=$(mktemp /tmp/tsdb_install_XXXXXX.sh)
      cat > "$SCRIPT_FILE" << 'TSEOF'
#!/bin/bash
set -euo pipefail

# 1. TimescaleDB YUM repo
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

# 2. Install TimescaleDB
dnf -y install timescaledb-2-postgresql-16

# 3. pg_config symlink
if [ ! -e /usr/pgsql-16/bin/pg_config ]; then
  mkdir -p /usr/pgsql-16/bin
  ln -sf /usr/bin/pg_config /usr/pgsql-16/bin/pg_config
fi

# 4. Create EBS lib dir
PG_EBS_LIBDIR=/var/lib/pgsql/lib
mkdir -p "$PG_EBS_LIBDIR"
chown postgres:postgres "$PG_EBS_LIBDIR"

# 5. Copy .so files to EBS
cp -f /usr/lib64/timescaledb-loader-pg16/timescaledb.so "$PG_EBS_LIBDIR/"
for so in /usr/lib64/timescaledb-pg16/*.so; do cp -f "$so" "$PG_EBS_LIBDIR/"; done

# 6. Symlinks in /usr/lib64/pgsql/ -> EBS copies
PG_LIBDIR=/usr/lib64/pgsql
ln -sf "$PG_EBS_LIBDIR/timescaledb.so" "$PG_LIBDIR/timescaledb.so"
for so in "$PG_EBS_LIBDIR"/timescaledb-*.so; do ln -sf "$so" "$PG_LIBDIR/"; done

# 6b. Symlink .control and .sql into AL2023 native share dir.
#     el8 RPM installs these under /usr/lib64/timescaledb-*-pg16/, not /usr/share.
SHARE_DIR=/usr/share/pgsql/extension
mkdir -p "$SHARE_DIR"
ln -sf /usr/lib64/timescaledb-loader-pg16/timescaledb.control "$SHARE_DIR/timescaledb.control"
for sql in /usr/lib64/timescaledb-pg16/timescaledb--*.sql; do
  ln -sf "$sql" "$SHARE_DIR/"
done

# 7. postgresql.conf settings (idempotent)
PG_CONF=/var/lib/pgsql/data/postgresql.conf
if ! grep -q "shared_preload_libraries" "$PG_CONF"; then
  echo "shared_preload_libraries = 'timescaledb'" >> "$PG_CONF"
fi
if ! grep -q "dynamic_library_path" "$PG_CONF"; then
  echo "dynamic_library_path = '\$libdir:/var/lib/pgsql/lib'" >> "$PG_CONF"
fi

# 8. Restart PostgreSQL
systemctl restart postgresql
TSEOF

      ENCODED=$(base64 -w 0 "$SCRIPT_FILE")
      JSON_FILE=$(mktemp /tmp/ssm_tsdb_XXXXXX.json)
      cat > "$JSON_FILE" << JSONEOF
{
  "InstanceIds": ["${aws_instance.main_db.id}"],
  "DocumentName": "AWS-RunShellScript",
  "Parameters": {
    "commands": ["echo $ENCODED | base64 -d | sudo bash"]
  }
}
JSONEOF

      COMMAND_ID=$(aws ssm send-command \
        --region ${var.region} \
        --cli-input-json file://"$JSON_FILE" \
        --query Command.CommandId \
        --output text)
      aws ssm wait command-executed \
        --region ${var.region} \
        --command-id "$COMMAND_ID" \
        --instance-id ${aws_instance.main_db.id}
      rm -f "$SCRIPT_FILE" "$JSON_FILE"
    EOC
  }

  depends_on = [aws_instance.main_db]
}

resource "null_resource" "main_db_sql" {
  triggers = {
    sql_hash = sha256(local.main_db_sql)
  }

  provisioner "local-exec" {
    command = <<-EOC
      SCRIPT_FILE=$(mktemp /tmp/db_init_XXXXXX.sh)
      cat > "$SCRIPT_FILE" << 'SQLEOF'
    ${local.main_db_sql}
    SQLEOF
      ENCODED=$(base64 -w 0 "$SCRIPT_FILE")
      JSON_FILE=$(mktemp /tmp/ssm_XXXXXX.json)
      cat > "$JSON_FILE" << JSONEOF
    {
      "InstanceIds": ["${aws_instance.main_db.id}"],
      "DocumentName": "AWS-RunShellScript",
      "Parameters": {
        "commands": ["echo $ENCODED | base64 -d | sudo bash"]
      }
    }
    JSONEOF
      COMMAND_ID=$(aws ssm send-command \
        --region ${var.region} \
        --cli-input-json file://"$JSON_FILE" \
        --query Command.CommandId \
        --output text)
      aws ssm wait command-executed \
        --region ${var.region} \
        --command-id "$COMMAND_ID" \
        --instance-id ${aws_instance.main_db.id}
      rm -f "$SCRIPT_FILE" "$JSON_FILE"
    EOC
  }

  depends_on = [null_resource.main_db_timescaledb]
}
