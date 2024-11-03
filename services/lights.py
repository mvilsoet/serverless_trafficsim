import boto3
import json
import os
from datetime import datetime, timedelta

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')
table = dynamodb.Table(os.getenv("DYNAMODB_TABLE"))
queue_url = os.getenv("TRAFFIC_LIGHT_QUEUE")

def lambda_handler(event, context):
    response = table.query(
        IndexName='EntityTypeIndex',
        KeyConditionExpression=Key('entity_type').eq('traffic_light')
    )
    traffic_lights = response['Items']
    
    for light in traffic_lights:
        new_state, next_change_time = calculate_next_state(light)
        table.update_item(
            Key={'entity_id': light['traffic_light_id']},
            UpdateExpression="set state=:s, next_change_time=:n",
            ExpressionAttributeValues={
                ':s': new_state,
                ':n': next_change_time.isoformat()
            }
        )
    
    message_body = json.dumps({'traffic_lights': traffic_lights})
    sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=message_body
    )

    return {'statusCode': 200, 'body': json.dumps('Traffic lights updated.')}

def calculate_next_state(light):
    current_state = light['state']
    new_state = 'GREEN' if current_state == 'RED' else 'RED'
    next_change_time = datetime.now() + timedelta(seconds=light['cycle_duration'])
    return new_state, next_change_time
