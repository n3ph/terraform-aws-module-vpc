#------------------------------------------------------------------------------#
# Providers
#------------------------------------------------------------------------------#

provider "aws" {
  alias = "dns"
}

provider "aws" {
  alias = "ses"
}

provider "aws" {
  alias = "connect"
}

#------------------------------------------------------------------------------#
# Locals
#------------------------------------------------------------------------------#

locals {
  name      = var.env == null ? replace(title(var.name), " ", "-") : format("%s-%s", replace(title(var.name), " ", "-"), title(var.env))
  subdomain = format("%s.ACME.cloud", replace(lower(var.name), " ", "-"))
  fqdn      = var.env == null ? local.subdomain : format("%s.%s", lower(var.env), local.subdomain)
}

#------------------------------------------------------------------------------#
# VPC
#------------------------------------------------------------------------------#

resource "aws_vpc" "main" {
  cidr_block       = var.cidr
  instance_tenancy = var.instance_tenancy

  enable_dns_hostnames = true
  enable_dns_support   = true

  assign_generated_ipv6_cidr_block = var.enable_ipv6

  tags = {
    Name      = local.name
    Domain    = local.fqdn
    Terraform = true
  }
}

#------------------------------------------------------------------------------#

output "id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_id" {
  description = "DEPRECATED output for the ID of the VPC, use id ouput"
  value       = aws_vpc.main.id
}

output "cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "ipv6_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.ipv6_cidr_block
}

#------------------------------------------------------------------------------#
# Public DNS Zone <env>.<project>.ACME.cloud.
#------------------------------------------------------------------------------#

resource "aws_route53_zone" "main" {
  name = local.fqdn

  tags = {
    Name      = local.name
    Type      = "Forward"
    Terraform = true
  }
}

# parent zone 'ACME.cloud.'
data "aws_route53_zone" "ACME_cloud" {
  name     = "ACME.cloud."
  provider = aws.dns
}

# NS record in the parent zone 'ACME.cloud.'
resource "aws_route53_record" "ACME_cloud_ns" {
  zone_id         = data.aws_route53_zone.ACME_cloud.zone_id
  name            = local.fqdn
  type            = "NS"
  ttl             = "30"
  allow_overwrite = true

  records = [
    aws_route53_zone.main.name_servers.0,
    aws_route53_zone.main.name_servers.1,
    aws_route53_zone.main.name_servers.2,
    aws_route53_zone.main.name_servers.3,
  ]

  provider = aws.dns
}

output "zone_id" {
  description = "Public DNS zone where VPC resources are registered"
  value       = aws_route53_zone.main.id
}

#------------------------------------------------------------------------------#
# SES validation of the public DNS zone
# TODO: remove the custom provider when SES is available in Frankfurt
#------------------------------------------------------------------------------#

resource "aws_ses_domain_identity" "main" {
  domain = local.fqdn

  provider = aws.ses
}

resource "aws_ses_domain_dkim" "main" {
  domain = aws_ses_domain_identity.main.domain

  provider = aws.ses
}

resource "aws_route53_record" "ses_verification" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_amazonses"
  type    = "TXT"
  ttl     = "600"
  records = [aws_ses_domain_identity.main.verification_token]
}

resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = aws_route53_zone.main.zone_id
  type    = "CNAME"
  ttl     = "600"

  name    = format("%s._domainkey.%s", aws_ses_domain_dkim.main.dkim_tokens[count.index], local.fqdn)
  records = [format("%s.dkim.amazonses.com", aws_ses_domain_dkim.main.dkim_tokens[count.index])]
}


#------------------------------------------------------------------------------#
# DHCP Options
#------------------------------------------------------------------------------#

resource "aws_vpc_dhcp_options" "main" {
  domain_name          = local.fqdn
  domain_name_servers  = ["AmazonProvidedDNS"]
  ntp_servers          = ["169.254.169.123"]
  netbios_name_servers = []
  netbios_node_type    = 2

  tags = {
    Name      = local.name
    Terraform = true
  }
}

resource "aws_vpc_dhcp_options_association" "main" {
  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.main.id
}

#------------------------------------------------------------------------------#
# VPN
#------------------------------------------------------------------------------#

resource "aws_vpn_gateway" "main" {
  count = var.enable_vpn_gateway ? 1 : 0

  vpc_id          = aws_vpc.main.id
  amazon_side_asn = var.vpn_gateway_asn

  tags = {
    Name      = local.name
    Terraform = true
  }
}

resource "aws_customer_gateway" "main" {
  count = var.enable_vpn_gateway ? length(var.vpn_customer_gateways) : 0

  bgp_asn    = var.vpn_customer_gateways[count.index]["bgp_asn"]
  ip_address = var.vpn_customer_gateways[count.index]["ip_address"]
  type       = "ipsec.1"

  tags = {
    Name      = local.name
    Terraform = true
  }
}

resource "aws_vpn_connection" "main" {
  count = var.enable_vpn_gateway ? length(var.vpn_customer_gateways) : 0

  vpn_gateway_id      = concat(aws_vpn_gateway.main.*.id, [""])[0]
  customer_gateway_id = aws_customer_gateway.main[count.index].id
  type                = "ipsec.1"

  tags = {
    Name      = local.name
    Terraform = true
  }
}

#------------------------------------------------------------------------------#

output "vgw_id" {
  description = "The ID of the VPN Gateway"
  value       = concat(aws_vpn_gateway.main.*.id, [""])[0]
}

#------------------------------------------------------------------------------#

resource "aws_sns_topic" "vpn" {
  name = "vpn-link-status"

  tags = {
    Name      = local.name
    Terraform = true
  }
}

resource "aws_cloudwatch_metric_alarm" "vpn_link_status" {
  count = var.enable_vpn_gateway ? length(var.vpn_customer_gateways) : 0

  alarm_name          = format("%s-link-status", aws_vpn_connection.main[count.index].id)
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "TunnelState"
  namespace           = "AWS/VPN"
  period              = "120"
  statistic           = "Minimum"
  threshold           = "1"

  dimensions = {
    VpnId = aws_vpn_connection.main[count.index].id
  }

  alarm_description = "This metric monitors VPN link status"
  alarm_actions     = [aws_sns_topic.vpn.arn]
  ok_actions        = [aws_sns_topic.vpn.arn]

  tags = {
    Name      = local.name
    Terraform = true
  }
}

#------------------------------------------------------------------------------#
# Service Endpoints
#------------------------------------------------------------------------------#

data "aws_vpc_endpoint_service" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  service = "s3"
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  vpc_id            = aws_vpc.main.id
  vpc_endpoint_type = "Gateway"
  service_name      = data.aws_vpc_endpoint_service.s3[0].service_name
  auto_accept       = true

  tags = {
    Name      = local.name
    Terraform = true
  }
}

data "aws_vpc_endpoint_service" "dynamodb" {
  count = var.enable_dynamodb_endpoint ? 1 : 0

  service = "dynamodb"
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = var.enable_dynamodb_endpoint ? 1 : 0

  vpc_id            = aws_vpc.main.id
  vpc_endpoint_type = "Gateway"
  service_name      = data.aws_vpc_endpoint_service.dynamodb[0].service_name
  auto_accept       = true

  tags = {
    Name      = local.name
    Terraform = true
  }
}
