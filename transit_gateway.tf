#------------------------------------------------------------------------------#
# VPC Attachment
#------------------------------------------------------------------------------#

resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  subnet_ids = [
    for subnet in aws_subnet.private :
    subnet.id
  ]

  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.main.id

  transit_gateway_default_route_table_association = var.transit_gateway_default_route_table_association
  transit_gateway_default_route_table_propagation = var.transit_gateway_default_route_table_propagation

  dns_support  = "enable"
  ipv6_support = var.enable_ipv6 ? "enable" : "disable"

  tags = {
    Name      = local.name
    Terraform = true
  }

  lifecycle {
    ignore_changes = [
      ipv6_support,
    ]
  }
}

output "transit_gateway_vpc_attachment_id" {
  value = aws_ec2_transit_gateway_vpc_attachment.main.id
}

#------------------------------------------------------------------------------#
# Route Table
#------------------------------------------------------------------------------#

resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = var.transit_gateway_id

  tags = {
    Name      = local.name
    Terraform = true
  }

  provider = aws.connect
}

output "transit_gateway_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.main.id
}

resource "aws_ec2_transit_gateway_route_table_association" "main" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.main.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id

  provider = aws.connect
}

#------------------------------------------------------------------------------#
# Propagations
#------------------------------------------------------------------------------#

resource "aws_ec2_transit_gateway_route_table_propagation" "main" {
  for_each = toset(var.transit_gateway_propagations[*].attachment_id)

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
  transit_gateway_attachment_id  = each.value

  provider = aws.connect
}

#------------------------------------------------------------------------------#
# Static Routes
#------------------------------------------------------------------------------#

resource "aws_ec2_transit_gateway_route" "main" {
  for_each = toset(var.transit_gateway_static_routes[*].attachment_id)

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
  transit_gateway_attachment_id  = each.value

  destination_cidr_block = element([
    for transit_gateway_static_route in var.transit_gateway_static_routes :
    transit_gateway_static_route.cidr_block
    if transit_gateway_static_route.attachment_id == each.value
  ], 0)

  provider = aws.connect
}
