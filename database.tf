#------------------------------------------------------------------------------#
# Database subnet
#------------------------------------------------------------------------------#

resource "aws_subnet" "database" {
  count = var.enable_database_subnets ? length(var.azs) : 0

  vpc_id                          = aws_vpc.main.id
  cidr_block                      = cidrsubnet(aws_vpc.main.cidr_block, 4, 11 + count.index)
  ipv6_cidr_block                 = var.enable_ipv6 ? cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 11 + count.index) : null
  availability_zone               = var.azs[count.index]
  assign_ipv6_address_on_creation = var.enable_ipv6

  tags = {
    Name      = format("Database-%s", var.azs[count.index])
    Project   = local.name
    Tier      = "Database"
    Terraform = true
  }
}

#------------------------------------------------------------------------------#

output "database_subnets" {
  description = "List of IDs of database subnets"
  value = [
    for subnet in aws_subnet.database :
    subnet.id
  ]
}

output "database_subnet_cidr_blocks" {
  description = "List of CIDR blocks of database subnets"
  value = [
    for subnet in aws_subnet.database :
    subnet.cidr_block
  ]
}

#------------------------------------------------------------------------------#
# Routes
#------------------------------------------------------------------------------#

resource "aws_route_table_association" "database" {
  count = var.enable_database_subnets && var.enable_private_subnets ? length(var.azs) : 0

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

#------------------------------------------------------------------------------#
# Reverse DNS Zone
#------------------------------------------------------------------------------#

resource "aws_route53_zone" "database" {
  count = var.enable_database_subnets ? length(var.azs) : 0

  vpc {
    vpc_id = aws_vpc.main.id
  }

  force_destroy = true

  name = format(
    "%s.%s.%s.in-addr.arpa.",
    split(".", split("/", aws_subnet.database[count.index].cidr_block)[0])[2],
    split(".", split("/", aws_subnet.database[count.index].cidr_block)[0])[1],
    split(".", split("/", aws_subnet.database[count.index].cidr_block)[0])[0]
  )

  tags = {
    Name      = format("database-%s", var.azs[count.index])
    Project   = local.name
    Tier      = "Database"
    Type      = "Reverse"
    Terraform = true
  }
}
