# Dedicated Neo4j connection secret consumed by application services.
# Unlike ai/rorr/{env} (created out-of-band and referenced as a data source),
# this per-concern secret is managed here. The neo4j instance bootstrap writes
# the live uri/username/password into it, so the initial values are empty
# placeholders and secret_string changes are ignored after creation.
resource "aws_secretsmanager_secret" "neo4j" {
  name        = "rorr/${var.env}/neo4j"
  description = "RORR Neo4j graph database connection info"

  tags = {
    Name      = "rorr-${var.env}-neo4j"
    Component = "neo4j"
  }
}

resource "aws_secretsmanager_secret_version" "neo4j" {
  secret_id = aws_secretsmanager_secret.neo4j.id
  secret_string = jsonencode({
    uri      = ""
    username = "neo4j"
    password = ""
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
