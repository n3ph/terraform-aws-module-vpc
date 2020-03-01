#------------------------------------------------------------------------------#
# Private subnet
#------------------------------------------------------------------------------#

resource "aws_subnet" "private" {
  count = var.enable_private_subnets ? length(var.azs) : 0

  vpc_id                          = aws_vpc.main.id
  cidr_block                      = cidrsubnet(aws_vpc.main.cidr_block, 4, 6 + count.index)
  ipv6_cidr_block                 = var.enable_ipv6 ? cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 6 + count.index) : null
  availability_zone               = var.azs[count.index]
  assign_ipv6_address_on_creation = var.enable_ipv6

  tags = {
    Name      = format("Private-%s", var.azs[count.index])
    Project   = local.name
    Tier      = "Private"
    Terraform = true
  }
}

#------------------------------------------------------------------------------#

output "private_subnets" {
  description = "List of IDs of private subnets"
  value = [
    for subnet in aws_subnet.private :
    subnet.id
  ]
}

output "private_subnet_cidr_blocks" {
  description = "List of CIDR blocks of private subnets"
  value = [
    for subnet in aws_subnet.private :
    subnet.cidr_block
  ]
}

#------------------------------------------------------------------------------#
# Private routes
#------------------------------------------------------------------------------#

locals {
  transit_gateway_propagation_cidr_blocks = distinct([
    for cidr_block in var.transit_gateway_propagations[*].cidr_block : cidr_block if cidr_block != null
  ])

  transit_gateway_propagation_ipv6_cidr_blocks = distinct([
    for ipv6_cidr_block in var.transit_gateway_propagations[*].ipv6_cidr_block : ipv6_cidr_block if ipv6_cidr_block != null
  ])
}

resource "aws_route_table" "private" {
  count = var.enable_private_subnets ? length(var.azs) : 0

  vpc_id = aws_vpc.main.id

  lifecycle {
    ignore_changes = [propagating_vgws]
  }

  # NAT Gateway
  dynamic "route" {
    for_each = [for ipv4_default_route in ["0.0.0.0/0"] : {
      cidr_block = ipv4_default_route
    } if var.enable_private_subnets && var.enable_nat_gateway]

    content {
      cidr_block     = route.value.cidr_block
      nat_gateway_id = aws_nat_gateway.public[count.index].id
    }
  }

  # IPv6 Gateway
  dynamic "route" {
    for_each = [for ipv6_default_route in ["::/0"] : {
      cidr_block = ipv6_default_route
    } if var.enable_private_subnets && var.enable_ipv6]

    content {
      ipv6_cidr_block        = route.value.cidr_block
      egress_only_gateway_id = aws_egress_only_internet_gateway.public[0].id
    }
  }

  # Transit Gateway dynamic ipv4 routes
  dynamic "route" {
    for_each = local.transit_gateway_propagation_cidr_blocks

    content {
      cidr_block         = route.value
      transit_gateway_id = var.transit_gateway_id
    }
  }

  # Transit Gateway dynamic ipv6 routes
  dynamic "route" {
    for_each = local.transit_gateway_propagation_ipv6_cidr_blocks

    content {
      ipv6_cidr_block    = route.value
      transit_gateway_id = var.transit_gateway_id
    }
  }


  # Transit Gateway static routes
  dynamic "route" {
    for_each = var.transit_gateway_static_routes[*].cidr_block

    content {
      cidr_block         = route.value
      transit_gateway_id = var.transit_gateway_id
    }
  }

  # VPC Peering
  dynamic "route" {
    for_each = [for vpc_peering_connection in data.aws_vpc_peering_connection.main : {
      vpc_peering_connection_id = vpc_peering_connection.id
      cidr_block                = vpc_peering_connection.cidr_block
    }]

    content {
      cidr_block                = route.value.cidr_block
      vpc_peering_connection_id = route.value.vpc_peering_connection_id
    }
  }

  tags = {
    Name      = var.azs[count.index]
    Tier      = "Private"
    Terraform = true
  }
}

resource "aws_route_table_association" "private" {
  count = var.enable_private_subnets ? length(var.azs) : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

#------------------------------------------------------------------------------#

output "private_route_tables" {
  value = [
    for route in aws_route_table.private :
    route.id
  ]
}

#------------------------------------------------------------------------------#
# Reverse DNS Zone
#------------------------------------------------------------------------------#

resource "aws_route53_zone" "private" {
  count = var.enable_private_subnets ? length(var.azs) : 0

  vpc {
    vpc_id = aws_vpc.main.id
  }

  force_destroy = true

  name = format(
    "%s.%s.%s.in-addr.arpa.",
    split(".", split("/", aws_subnet.private[count.index].cidr_block)[0])[2],
    split(".", split("/", aws_subnet.private[count.index].cidr_block)[0])[1],
    split(".", split("/", aws_subnet.private[count.index].cidr_block)[0])[0]
  )

  tags = {
    Name      = format("Private-%s", var.azs[count.index])
    Project   = local.name
    Tier      = "Private"
    Type      = "Reverse"
    Terraform = true
  }
}

#------------------------------------------------------------------------------#

output "private_reverse_zones" {
  value = [
    for reverse_zone in aws_route53_zone.private :
    reverse_zone.id
  ]
}

#------------------------------------------------------------------------------#
# VPN
#------------------------------------------------------------------------------#

resource "aws_vpn_gateway_route_propagation" "private" {
  count = var.enable_private_subnets && var.enable_vpn_gateway && var.vpn_propagate_private_routes ? length(var.azs) : 0

  route_table_id = aws_route_table.private[count.index].id
  vpn_gateway_id = aws_vpn_gateway.main[0].id
}

#------------------------------------------------------------------------------#
# Service Endpoints
#------------------------------------------------------------------------------#

resource "aws_vpc_endpoint_route_table_association" "private_s3" {
  count = var.enable_private_subnets && var.enable_s3_endpoint ? length(var.azs) : 0

  vpc_endpoint_id = aws_vpc_endpoint.s3[0].id
  route_table_id  = aws_route_table.private[count.index].id
}

resource "aws_vpc_endpoint_route_table_association" "private_dynamodb" {
  count = var.enable_private_subnets && var.enable_dynamodb_endpoint ? length(var.azs) : 0

  vpc_endpoint_id = aws_vpc_endpoint.dynamodb[0].id
  route_table_id  = aws_route_table.private[count.index].id
}

#------------------------------------------------------------------------------#
# Peering Acceptance
#------------------------------------------------------------------------------#

data "aws_vpc_peering_connection" "main" {
  for_each = toset(var.vpc_peering_ids)

  id = each.value
}

resource "aws_vpc_peering_connection_accepter" "main" {
  for_each = toset(var.vpc_peering_ids)

  vpc_peering_connection_id = data.aws_vpc_peering_connection.main[each.value].id
  auto_accept               = true
}

resource "aws_vpc_peering_connection_options" "main" {
  for_each = toset(var.vpc_peering_ids)

  vpc_peering_connection_id = data.aws_vpc_peering_connection.main[each.value].id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}
