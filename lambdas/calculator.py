import boto3
import json
import os
import random
from datetime import datetime, timedelta

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.getenv("DYNAMODB_TABLE"))

def lambda_handler(event, context):
    # Parse input parameters from the event
    simulation_params = json.loads(event['body'])
    time_step = simulation_params.get("time_step", 1)  # Default to 1 second if not provided

    cars = []
    stats = {"total_distance": 0, "average_speed": 0}

    # Simulate movements for 5 cars
    for car_id in range(1, 6):
        speed = random.randint(10, 50)  # Random speed in units per second
        direction = {"x": random.choice([-1, 1]), "y": random.choice([-1, 1])}
        
        # Calculate position based on speed, direction, and time_step
        position = {
            "x": direction["x"] * speed * time_step,
            "y": direction["y"] * speed * time_step
        }
        distance = speed * time_step
        stats["total_distance"] += distance
        cars.append({"car_id": car_id, "position": position, "speed": speed})
    
    # Calculate average speed
    stats["average_speed"] = sum(car["speed"] for car in cars) / len(cars)

    # Prepare and save the result to DynamoDB
    result = {
        "timestamp": datetime.now().isoformat(),
        "cars": cars,
        "stats": stats
    }
    table.put_item(Item=result)

    return {'statusCode': 200, 'body': json.dumps('Simulation completed and results saved.')}
