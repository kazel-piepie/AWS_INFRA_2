resource "null_resource" "main_db_sql" {
  triggers = {
    sql_hash = sha256(local.main_db_sql)
  }

  provisioner "local-exec" {
    command = <<-EOC
      COMMAND_ID=$(aws ssm send-command \
        --region ${var.region} \
        --instance-ids ${aws_instance.main_db.id} \
        --document-name AWS-RunShellScript \
        --parameters commands=["${local.main_db_sql}"] \
        --query Command.CommandId \
        --output text)
      aws ssm wait command-executed \
        --region ${var.region} \
        --command-id $COMMAND_ID \
        --instance-id ${aws_instance.main_db.id}
    EOC
  }

  depends_on = [aws_instance.main_db]
}
