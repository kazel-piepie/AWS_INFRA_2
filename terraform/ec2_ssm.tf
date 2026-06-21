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

  depends_on = [aws_instance.main_db]
}
