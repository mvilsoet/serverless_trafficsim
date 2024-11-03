import boto3
import json
import os

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.getenv("DYNAMODB_TABLE"))

def lambda_handler(event, context):
    # Parse road updates from the incoming event (e.g., API Gateway payload)
    road_updates = json.loads(event['body'])
    
    # Loop over each road in the update request
    for road in road_updates:
        # Update DynamoDB with the new road configuration values
        table.update_item(
            Key={'entity_id': road['road_id']},  # Identify the road by its unique ID
            UpdateExpression="set is_valid=:v, max_speed=:m",
            ExpressionAttributeValues={
                ':v': road['is_valid'],  # Set to True for open roads, False for closed
                ':m': road['max_speed']  # Update the maximum speed limit
            }
        )

    return {'statusCode': 200, 'body': json.dumps('Road configurations updated.')}
