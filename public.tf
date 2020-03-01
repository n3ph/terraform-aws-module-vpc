#------------------------------------------------------------------------------#
# Public subnet
#------------------------------------------------------------------------------#

resource "aws_subnet" "public" {
  count = var.enable_public_subnets ? length(var.azs) : 0

  vpc_id                          = aws_vpc.main.id
  cidr_block                      = cidrsubnet(aws_vpc.main.cidr_block, 4, 1 + count.index)
  ipv6_cidr_block                 = var.enable_ipv6 ? cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 1 + count.index) : null
  availability_zone               = var.azs[count.index]
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = var.enable_ipv6

  tags = {
    Name      = format("Public-%s", var.azs[count.index])
    Project   = local.name
    Tier      = "Public"
    Terraform = true
  }
}

#------------------------------------------------------------------------------#

output "public_subnets" {
  description = "List of IDs of public subnets"
  value = [
    for subnet in aws_subnet.public :
    subnet.id
  ]
}

#------------------------------------------------------------------------------#
# Gateways
#------------------------------------------------------------------------------#

resource "aws_internet_gateway" "public" {
  count = var.enable_public_subnets ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = {
    Name      = local.name
    Terraform = true
  }
}

resource "aws_egress_only_internet_gateway" "public" {
  count = var.enable_ipv6 ? 1 : 0

  vpc_id = aws_vpc.main.id
}

resource "aws_eip" "public" {
  count = var.enable_public_subnets && var.enable_nat_gateway ? length(var.azs) : 0

  vpc = true

  tags = {
    Name      = format("NGW-%s", var.azs[count.index])
    Project   = local.name
    Terraform = true
  }
}

resource "aws_nat_gateway" "public" {
  count = var.enable_public_subnets && var.enable_nat_gateway ? length(var.azs) : 0

  allocation_id = aws_eip.public[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name      = var.azs[count.index]
    Project   = local.name
    Terraform = true
  }
}

#------------------------------------------------------------------------------#

output "nat_gateway_public_ips" {
  value = aws_nat_gateway.public
}

#------------------------------------------------------------------------------#
# Routes
#------------------------------------------------------------------------------#

resource "aws_route_table" "public" {
  count = var.enable_public_subnets ? 1 : 0

  vpc_id = aws_vpc.main.id

  # NAT Gateway
  dynamic "route" {
    for_each = [for ipv4_default_route in ["0.0.0.0/0"] : {
      cidr = ipv4_default_route
    } if var.enable_public_subnets && var.enable_nat_gateway]

    content {
      cidr_block = route.value.cidr
      gateway_id = aws_internet_gateway.public[0].id
    }
  }

  # IPv6 Gateway
  dynamic "route" {
    for_each = [for ipv6_default_route in ["::/0"] : {
      cidr = ipv6_default_route
    } if var.enable_public_subnets && var.enable_ipv6]

    content {
      ipv6_cidr_block = route.value.cidr
      gateway_id      = aws_internet_gateway.public[0].id
    }
  }

  tags = {
    Name      = "Public"
    Project   = local.name
    Tier      = "Public"
    Terraform = true
  }
}

resource "aws_route_table_association" "public" {
  count = var.enable_public_subnets ? length(var.azs) : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

#------------------------------------------------------------------------------#

output "public_route_tables" {
  value = aws_route_table.public
}

#------------------------------------------------------------------------------#
# Reverse DNS Zone
#------------------------------------------------------------------------------#

resource "aws_route53_zone" "public" {
  count = var.enable_public_subnets ? length(var.azs) : 0

  vpc {
    vpc_id = aws_vpc.main.id
  }

  force_destroy = true

  name = format(
    "%s.%s.%s.in-addr.arpa.",
    split(".", split("/", aws_subnet.public[count.index].cidr_block)[0])[2],
    split(".", split("/", aws_subnet.public[count.index].cidr_block)[0])[1],
    split(".", split("/", aws_subnet.public[count.index].cidr_block)[0])[0]
  )

  tags = {
    Name      = format("Public-%s", var.azs[count.index])
    Project   = local.name
    Tier      = "Public"
    Type      = "Reverse"
    Terraform = true
  }
}

#------------------------------------------------------------------------------#

output "public_reverse_zones" {
  value = [
    for reverse_zone in aws_route53_zone.public :
    reverse_zone.id
  ]
}

#------------------------------------------------------------------------------#
# Service Endpoints
#------------------------------------------------------------------------------#

resource "aws_vpc_endpoint_route_table_association" "public_s3" {
  count = var.enable_public_subnets && var.enable_s3_endpoint ? 1 : 0

  vpc_endpoint_id = aws_vpc_endpoint.s3[0].id
  route_table_id  = aws_route_table.public[0].id
}

resource "aws_vpc_endpoint_route_table_association" "public_dynamodb" {
  count = var.enable_public_subnets && var.enable_dynamodb_endpoint ? 1 : 0

  vpc_endpoint_id = aws_vpc_endpoint.dynamodb[0].id
  route_table_id  = aws_route_table.public[0].id
}
