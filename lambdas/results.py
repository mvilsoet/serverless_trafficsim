import boto3
import json
import os
from decimal import Decimal

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.getenv("DYNAMODB_TABLE"))

# Custom encoder to handle Decimal types
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            # Convert Decimal to float or string (based on your requirements)
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

def lambda_handler(event, context):
    # Retrieve all simulation data from DynamoDB
    response = table.scan()
    simulation_data = response['Items']
    
    return {
        'statusCode': 200,
        'body': json.dumps(simulation_data, cls=DecimalEncoder)
    }
