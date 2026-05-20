# Simple Route53 ALIAS A-record pointing at an ALB.

variable "hosted_zone_id" { type = string }
variable "name" { type = string }
variable "alias_target_dns_name" { type = string }
variable "alias_target_zone_id" { type = string }

resource "aws_route53_record" "alias" {
  zone_id = var.hosted_zone_id
  name    = var.name
  type    = "A"

  alias {
    name                   = var.alias_target_dns_name
    zone_id                = var.alias_target_zone_id
    evaluate_target_health = false
  }
}

output "fqdn" { value = aws_route53_record.alias.fqdn }
