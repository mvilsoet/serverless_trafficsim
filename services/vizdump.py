import boto3
import json
import os

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.getenv("DYNAMODB_TABLE"))

def lambda_handler(event, context):
    response = table.scan()
    simulation_data = response['Items']
    return {
        'statusCode': 200,
        'body': json.dumps(simulation_data)
    }
