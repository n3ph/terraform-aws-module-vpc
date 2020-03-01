# Virtual Private Cloud Module
This module provides functionality for creating an vpc with following functionality:

* Subnets (IPv4 / IPv6)  
  * public  
  * private  
  * database  
* Routing (IPv4 / IPv6)  
  * Internet Gateway  
  * NAT Gateway  
  * Virtual Private Gateway  
  * Transit Gateway  
  * VPC Peering  
* DNS Zones  
  * ReverseDNS Zones (IPv4)  
  * ForwardDNS Zone (IPv4)  
* S3 / DynamoDB Endpoints  
* DHCP Options (DNS)

## Details
### Subnetting
#### IPv4
As we want to care about ReverseDNS it is much simpler to use **/24** CIDR blocks.
If we use a maximum of 3 different subnet types in up to 5 different AZs, we would fit with one **/20** CIDR block per VPC...

#### IPv6
The module is also capable of configuring IPv6 for the subnets.
Since AmazonAWS is providing a /56 Prefix per VPC we could simply split this into /64 blocks.

### Routing
All Ingress and Egress IPv4/IPv6 Traffic will be controlled via the [Security-Group Module](https://git.ACME.de/devops/terraform-aws/modules/security_group).

#### Internet / NAT Gateway
Public subnets will get an Internet Gateway per default while Private Subnets will get a NAT-Gateway per AZ when `enable_nat_gateway` is true.

All Subnets have IPv6 routing available if `enable_ipv6` is true.

#### VPN Gateway
**WIP:** Support for Spoke VPC connection to Transit VPC already integrated

### ReverseDNS
The module will create all necessary reverse DNS zones for all IPv4 subnets in order to work properly with the [Autoscaling-Group Module](https://git.ACME.office/devops/terraform-aws/modules/asg)

## Usage
### General
`name` - Name to be used on resources as identifier (**required**)  
`env` - Environment to be used on resources as identifier (**required**)

### VPC
`cidr` - A CIDR Block notation of the whole VPC (default: **required**)  
`azs` - List of AZs the VPC should be built in (default: **["eu-central-1a", "eu-central-1b", "eu-central-1c"]**)  
`instance_tenancy` - A tenancy option for instances launched into the VPC (default: **default**)  
`enable_ipv6` - Should be false if you do not want IPv6 (default: **false**)

### Subnets
`enable_public_subnets` - Switch to create public subnets (default: **false**)  
`enable_private_subnets` - Switch to create private subnets (default: **false**)  
`enable_database_subnets` - Switch to create database subnets (**false**)  
`enable_ddns` - Set to enable DDNS in forward and reverse dns zone (**false**)

### Gateway
#### NAT
`enable_nat_gateway` - Should be true if you want to provision NAT Gateways for each of your private networks (Default: **false**)

#### VPN
`enable_vpn_gateway` - Should be true if you want to create a new VPN Gateway resource and attach it to the VPC (Default: **false**)  
`vpn_gateway_asn` - Should be 16bit or 64bit ASN for VPN Gateway (Default: **_empty_**)  
`vpn_propagate_private_routes` - Should be true if you want route table propagation (Default: **false**)  
`vpn_customer_gateways` - List of maps of VPN Transit Gateways (Default: **[{}]**)

Example:
```hcl
vpn_customer_gateways = [
  {
    ip_address = "23.42.23.42"
    bgp_asn    = 65001
  },
]
```

#### Transit Gateway ####
`transit_gateway_id` - ID of Transit Gateway (Default: **required**)  
`transit_gateway_propagations` - List of Transit Gateway Attachment IDs to propagate into Transit Gateway Route Table - (Default: **[]**)  
`transit_gateway_static_routes` - List of Map of Transit Gateway Attachment ID and static route to propagate into Transit Gateway Route Table - (Default: **[{}]**)  
`transit_gateway_vpc_routes` - List of CIDR blocks to route via Transit Gateway - (Default: **[]**)

Example:
```hcl
enable_transit_gateway_attachment = true

transit_gateway_id = data.aws_ec2_transit_gateway.connect.id

transit_gateway_vpc_routes = [
  "10.0.0.0/13",
  "10.128.0.0/21"
]

ransit_gateway_propagations = [data.aws_ec2_transit_gateway_vpc_attachment.connect.id]

transit_gateway_static_routes = [
  {
    attachment_id = "data.aws_ec2_transit_gateway_vpn_attachment.dfb_saphec_ffm.id"
    route         = "172.19.144.0/24"
  },
  {
    attachment_id = "data.aws_ec2_transit_gateway_vpn_attachment.dfb_saphec_ffm.id"
    route         = "172.19.145.0/24"
  }
]
```

#### VPC Peering Attachment
`vpc_peering_ids` - List of VPC Peering IDs to associate with - (Default: **[]**)  

### VPC Private Endpoints
`enable_dynamodb_endpoint` - Should be true if you want to provision a DynamoDB endpoint to the VPC (Default: **false**)  
`enable_s3_endpoint` - Should be true if you want to provision an S3 endpoint to the VPC - (Default: **false**)

## TODO
### Implement
* IPv6 ReverseDNS (https://github.com/hashicorp/terraform/issues/9404)
* EC2 Resource Tagging for Transit Gateway Attachments (https://github.com/terraform-providers/terraform-provider-aws/pull/8457)
