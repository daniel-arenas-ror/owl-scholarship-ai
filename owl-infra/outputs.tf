output "public_ip" {
  description = "Elastic IP of the app host"
  value       = aws_eip.app.public_ip
}

output "instance_id" {
  description = "EC2 instance id (use with: aws ssm start-session --target <id>)"
  value       = aws_instance.app.id
}

output "ecr_registry" {
  description = "ECR registry host for docker login / image push"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "ecr_repository_urls" {
  description = "Push targets per service"
  value       = { for k, r in aws_ecr_repository.service : k => r.repository_url }
}

output "nameservers" {
  description = "Set these at your domain registrar (empty when domain is unset)"
  value       = var.domain == "" ? [] : aws_route53_zone.main[0].name_servers
}
