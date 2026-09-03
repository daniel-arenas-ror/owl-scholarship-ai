locals {
  user_data = templatefile("${path.module}/instance/bootstrap.sh.tftpl", {
    compose_prod    = file("${path.module}/instance/docker-compose.prod.yml")
    caddyfile       = file("${path.module}/instance/Caddyfile")
    initdb_sql      = file("${path.module}/instance/initdb/10-databases.sql")
    deploy_sh       = file("${path.module}/instance/deploy.sh")
    region          = var.region
    ssm_prefix      = var.ssm_prefix
    compose_version = var.compose_version
  })
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023_arm.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  tags = { Name = "${local.name}-app" }
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"
  tags     = { Name = "${local.name}-app" }
}
