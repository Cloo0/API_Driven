import json
import os
import boto3

def lambda_handler(event, context):
    endpoint = f"http://{os.environ.get('LOCALSTACK_HOSTNAME', 'localhost')}:4566"

    ec2 = boto3.client(
        'ec2',
        endpoint_url=endpoint,
        region_name='us-east-1',
        aws_access_key_id='test',
        aws_secret_access_key='test',
    )

    try:
        # Parse du body
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body') or event

        # L'action peut venir : soit du path (/ec2/start), soit du body
        action = None
        path = event.get('path', '') or event.get('resource', '')
        if path.endswith('/start'):
            action = 'start'
        elif path.endswith('/stop'):
            action = 'stop'
        elif path.endswith('/status'):
            action = 'status'
        else:
            action = body.get('action')

        instance_id = body.get('instance_id')

        if not instance_id:
            return {'statusCode': 400,
                    'body': json.dumps({'error': "instance_id requis dans le body"})}

        if action == 'start':
            result = ec2.start_instances(InstanceIds=[instance_id])
        elif action == 'stop':
            result = ec2.stop_instances(InstanceIds=[instance_id])
        elif action == 'status':
            result = ec2.describe_instances(InstanceIds=[instance_id])
        else:
            return {'statusCode': 400,
                    'body': json.dumps({'error': "action doit etre start, stop ou status"})}

        return {
            'statusCode': 200,
            'body': json.dumps({'action': action, 'instance_id': instance_id,
                                'result': result}, default=str)
        }

    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
