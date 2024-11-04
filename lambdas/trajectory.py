import boto3
import json
import os
from datetime import datetime

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')
table = dynamodb.Table(os.getenv("DYNAMODB_TABLE"))
queue_url = os.getenv("VEHICLE_TRAJECTORY_QUEUE")

def lambda_handler(event, context):
    # Query only vehicles using the GSI
    response = table.query(
        IndexName='EntityTypeIndex',  # GSI on 'entity_type' for filtering 'vehicle'
        KeyConditionExpression=Key('entity_type').eq('vehicle')
    )
    vehicles = response['Items']
    
    for vehicle in vehicles:
        vehicle['position'] = update_position(vehicle['position'], vehicle['speed'], vehicle['direction'])
        vehicle['last_updated'] = datetime.now().isoformat()

        # Update vehicle position in DynamoDB
        table.update_item(
            Key={'entity_id': vehicle['vehicle_id']},
            UpdateExpression="set position=:p, last_updated=:l",
            ExpressionAttributeValues={
                ':p': vehicle['position'],
                ':l': vehicle['last_updated']
            }
        )

    # Send updated vehicle data to SQS
    message_body = json.dumps({'vehicles': vehicles})
    sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=message_body
    )

    return {'statusCode': 200, 'body': json.dumps('Vehicle trajectories updated.')}

def update_position(position, speed, direction):
    # Dummy position calculation
    return {
        'x': position['x'] + speed * direction['x'],
        'y': position['y'] + speed * direction['y']
    }
