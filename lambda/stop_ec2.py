import boto3
import os

def handler(event, context):
    ec2 = boto3.client('ec2')
    instance_id = os.environ['INSTANCE_ID']
    
    print(f"Stopping instance: {instance_id}")
    ec2.stop_instances(InstanceIds=[instance_id])
    
    return {
        'statusCode': 200,
        'body': f'Successfully stopped instance {instance_id}'
    }
