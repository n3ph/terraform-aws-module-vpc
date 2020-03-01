import json
import boto3

# TODO: add exception handling
# from botocore.exceptions import ClientError

# globals
r53 = boto3.client('route53')

# R53 helpers {{{
def upsert_record(
        *,                      # force using keyword arguments
        zone_id,
        record_type = 'A',
        name,
        value,
        ttl = 300):

    print(
        "Zone '{}': UPSERT '{}' record '{}' -> '{}'.. ".format(
            zone_id, record_type, name, value),
        end = '')

    # create the resource record
    rr = {
        'Type': record_type,
        'Name': name,
        'ResourceRecords': [{ 'Value': value }],
        'TTL': ttl
    }

    # insert/update the resource record set
    r53.change_resource_record_sets(
        HostedZoneId = zone_id,
        ChangeBatch = {
            'Changes': [{
                'Action': 'UPSERT',
                'ResourceRecordSet': rr
            }]
        })

    print("OK")

    # return the zone_id and the rr as a result
    return {
        'HostedZoneId': zone_id,
        'ResourceRecordSet': rr
        }



def delete_record(r):

    print(
        "Zone '{}': DELETE RR {}..".format(
            r['HostedZoneId'],
            json.dumps(r['ResourceRecordSet'], separators=(',', ':')),
        end = ''))

    r53.change_resource_record_sets(
        HostedZoneId = r['HostedZoneId'],
        ChangeBatch = {
            'Changes': [{
                'Action': 'DELETE',
                'ResourceRecordSet': r['ResourceRecordSet']
            }]
        })

    print("OK")
    


def get_zone_id(name):
    return r53.list_hosted_zones_by_name(DNSName=name)['HostedZones'][0]['Id'].split('/')[2]

def get_tags(kv):
    return dict(map(lambda x: (x['Key'], x['Value']), kv))
# }}}

# on instance launch
def on_launch(event):

    # parse the event details
    instance_id = event['detail']['EC2InstanceId']
    subnet_id = event['detail']['Details']['Subnet ID']
    asg_name = event['detail']['AutoScalingGroupName']

    # create the relevant objects
    ec2 = boto3.resource('ec2')

    instance = ec2.Instance(instance_id)

    vpc = ec2.Vpc(instance.vpc_id)
    vpc_tags = get_tags(vpc.tags)

    subnet = ec2.Subnet(subnet_id)

    # domain is VPC name
    domain = vpc_tags['Domain']

    # define fqdn as <asg_name>-<instance_id>.<domain>
    fqdn = "{}-{}.{}".format(
        asg_name,
        instance_id.split("i-", 1).pop(),
        domain
    )

    reverse_fqdn = '.'.join(
        reversed(instance.private_ip_address.split('.'))
    ) + '.in-addr.arpa.'

    # TODO: more elegant way?
    reverse_zone_name = '.'.join(reverse_fqdn.split('.')[1:])

    # insert/update the records into the forward/reverse DNS zones
    forward_zone_id = get_zone_id(domain)
    reverse_zone_id = get_zone_id(reverse_zone_name)

    tags = []

    # choose between public/private ip to be saved in the forward DNS zone
    if subnet.map_public_ip_on_launch:
        ip = instance.public_ip_address
    else:
        ip = instance.private_ip_address

    tags.append({
        'Key': 'Name',
        'Value': fqdn
    })

    tags.append({
        'Key': 'lambda:ddns:ForwardRR',
        'Value': json.dumps(
            upsert_record(
                zone_id     = forward_zone_id,
                name        = fqdn,
                value       = ip),
            separators=(',', ':'))
    })

    tags.append({
        'Key': 'lambda:ddns:ReverseRR',
        'Value': json.dumps(
            upsert_record(
                record_type = 'PTR',
                zone_id     = reverse_zone_id,
                name        = reverse_fqdn,
                value       = fqdn),
            separators=(',', ':'))
    })

    # save the ZoneIDs and RRs in the instance tags for deletion later
    instance.create_tags(Tags=tags)
        

        
def on_termination(event):

    # fetch the instance tags
    instance_id = event['detail']['EC2InstanceId']
    ec2 = boto3.resource('ec2')
    instance = ec2.Instance(instance_id)
    instance_tags = get_tags(instance.tags)

    # remove its DNS records
    for tag in ['lambda:ddns:ForwardRR', 'lambda:ddns:ReverseRR']:
        delete_record(json.loads(instance_tags[tag]))


# Lambda Handler {{{
def handler(event, context):

    # print the event received
    print(json.dumps(event))

    # on instance launch event
    if event['detail-type'] == 'EC2 Instance Launch Successful':
        on_launch(event)

    # on instance termination
    elif event['detail-type'] == 'EC2 Instance Terminate Successful':
        on_termination(event)

# }}}
