import boto3
import json
import os
import random
from datetime import datetime
from decimal import Decimal

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.getenv("DYNAMODB_TABLE"))

def lambda_handler(event, context):
    try:
        # Parse input parameters from the event
        simulation_params = json.loads(event['body'])
        time_step = simulation_params.get("time_step", 1)
        
        # Validate time_step is a positive number
        if not isinstance(time_step, (int, float)) or time_step <= 0:
            return {
                'statusCode': 400,
                'body': json.dumps("Invalid time_step: must be a positive number.")
            }
        
        # Convert time_step to Decimal for DynamoDB compatibility
        time_step = Decimal(str(time_step))

        cars = []
        stats = {"total_distance": Decimal('0'), "average_speed": Decimal('0')}

        # Simulate movements for 5 cars
        for car_id in range(1, 6):
            speed = random.randint(10, 50)  # Random speed in units per second
            direction = {"x": random.choice([-1, 1]), "y": random.choice([-1, 1])}
            
            # Calculate position based on speed, direction, and time_step
            position = {
                "x": Decimal(direction["x"]) * Decimal(speed) * time_step,
                "y": Decimal(direction["y"]) * Decimal(speed) * time_step
            }
            distance = Decimal(speed) * time_step
            stats["total_distance"] += distance
            cars.append({"car_id": car_id, "position": position, "speed": Decimal(speed)})
        
        # Calculate average speed
        stats["average_speed"] = sum(car["speed"] for car in cars) / Decimal(len(cars))

        # Prepare and save the result to DynamoDB
        result = {
            "timestamp": datetime.now().isoformat(),
            "cars": cars,
            "stats": stats
        }
        table.put_item(Item=result)

        return {'statusCode': 200, 'body': json.dumps('Simulation completed and results saved.')}
    
    except Exception as e:
        # Handle any other unexpected errors
        return {
            'statusCode': 500,
            'body': json.dumps(f"An error occurred: {str(e)}")
        }
