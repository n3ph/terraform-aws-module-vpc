#------------------------------------------------------------------------------#
# Global
#------------------------------------------------------------------------------#

variable "name" {
  description = "Name to be used on resources as identifier"
  type        = string
}

variable "env" {
  description = "Environment to be used on resources as identifier"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------#
# VPC
#------------------------------------------------------------------------------#
#

variable "cidr" {
  description = "A CIDR Block notation of the whole VPC"
  type        = string
}

variable "azs" {
  description = "List of AZs the VPC should be built in"
  default = [
    "eu-central-1a",
    "eu-central-1b",
    "eu-central-1c"
  ]
}

variable "instance_tenancy" {
  description = "Tenancy option for instances launched into the VPC"
  default     = "default"
}

variable "enable_ipv6" {
  description = "Set to true if you want to enable IPv6 within the VPC"
  default     = false
}

#------------------------------------------------------------------------------#
# Subnets
#------------------------------------------------------------------------------#

variable "enable_public_subnets" {
  description = "Set to false to disable creating the public subnets"
  default     = false
}

variable "enable_private_subnets" {
  description = "Set to false to disable creating the private subnets"
  default     = false
}

variable "enable_database_subnets" {
  description = "Set to false to disable creating the database subnets"
  default     = false
}

variable "enable_ddns" {
  description = "Set to enable DDNS in forward and reverse dns zone"
  default     = false
}

#------------------------------------------------------------------------------#
# Gateway
# TODO: rebuild to support AWS transit gateway
#------------------------------------------------------------------------------#

variable "enable_nat_gateway" {
  description = "Set to false to disable creating the NAT gateways"
  default     = false
}

variable "enable_vpn_gateway" {
  description = "Set to true to enable creating the VPN gateway attached to this VPC"
  default     = false
}

variable "vpn_gateway_asn" {
  description = "16bit or 64bit AS number of the VPN gateway"
  default     = null
}

variable "vpn_propagate_private_routes" {
  description = "Set to true to enable propagation of the private subnet routes via the VPN gateway"
  default     = false
}

variable "vpn_customer_gateways" {
  description = "List of maps of VPN customer gateways"
  type = list(object({
    ip_address = string
    bgp_asn    = number
  }))
  default = []
}

#------------------------------------------------------------------------------#
# Endpoints
#------------------------------------------------------------------------------#

variable "enable_dynamodb_endpoint" {
  description = "Should be true if you want to provision a DynamoDB endpoint to the VPC"
  default     = false
}

variable "enable_s3_endpoint" {
  description = "Should be true if you want to provision an S3 endpoint to the VPC"
  default     = false
}

#------------------------------------------------------------------------------#
# Transit Gateway
#------------------------------------------------------------------------------#

variable "transit_gateway_id" {
  description = "ID of Transit Gateway"
  type        = string
}

variable "transit_gateway_propagations" {
  description = "List of maps of Transit Gateway Attachment IDs to propagate into Transit Gateway Route Table"
  default     = []
  type = list(object({
    attachment_id   = string
    cidr_block      = string
    ipv6_cidr_block = string
  }))
}

variable "transit_gateway_static_routes" {
  description = "List of maps of Transit Gateway Attachment IDs to propagate into Transit Gateway Route Table"
  default     = []
  type = list(object({
    attachment_id = string
    cidr_block    = string
  }))
}

variable "transit_gateway_default_route_table_association" {
  description = "Whether the VPC Attachment should be associated with the EC2 Transit Gateway association default route table"
  default     = true
}

variable "transit_gateway_default_route_table_propagation" {
  description = "Whether the VPC Attachment should propagate routes with the EC2 Transit Gateway propagation default route table"
  default     = true
}

#------------------------------------------------------------------------------#
# Peering
#------------------------------------------------------------------------------#

variable "vpc_peering_ids" {
  description = "List of VPC Peering IDs to accept and route to"
  default     = []
}

variable "vpc_peering_routes" {
  description = "List of VPC Peerings to route to [HACK]"
  type = list(object({
    peering_id = string
    cidr_block = string
  }))
  default = []
}
