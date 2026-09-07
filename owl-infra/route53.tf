# Optional: only when var.domain is set. Creates a hosted zone and points the
# apex plus the admin. subdomain at the Elastic IP. Update your registrar's
# nameservers to the zone's NS records (see `terraform output nameservers`).
# owl-api has no public hostname — only owl-admin reaches it, internally.
resource "aws_route53_zone" "main" {
  count = var.domain == "" ? 0 : 1
  name  = var.domain
}

resource "aws_route53_record" "a" {
  for_each = var.domain == "" ? toset([]) : toset([
    var.domain,
    "admin.${var.domain}",
  ])

  zone_id = aws_route53_zone.main[0].zone_id
  name    = each.value
  type    = "A"
  ttl     = 300
  records = [aws_eip.app.public_ip]
}
