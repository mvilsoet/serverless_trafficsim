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
        # Process each record from the SQS queue
        for record in event['Records']:
            # Parse the SQS message
            message = json.loads(record['body'])

            # Check if the message is a SimulationRequest
            if message.get("messageType") != "SimulationRequest":
                continue
            
            # Extract simulation parameters
            simulation_params = message.get("simulationParams", {})
            time_step = Decimal(str(simulation_params.get("time_step", 1.0)))
            vehicle_count = int(simulation_params.get("vehicle_count", 5))

            # Validate parameters
            if time_step <= 0 or vehicle_count <= 0:
                continue  # Skip invalid message

            # Initialize stats and cars data
            cars = []
            stats = {
                "total_distance": 0,
                "total_time": 0,
                "total_speed": 0
            }

            # Run simulation
            for _ in range(vehicle_count):
                speed = random.uniform(20, 100)
                distance = speed * float(time_step)
                stats["total_distance"] += distance
                stats["total_speed"] += speed
                stats["total_time"] += time_step
                cars.append({
                    "speed": speed,
                    "distance": distance,
                    "time_step": float(time_step)
                })

            # Calculate averages
            stats["average_speed"] = stats["total_speed"] / vehicle_count
            stats["average_time"] = stats["total_time"] / vehicle_count

            # Prepare data for DynamoDB
            item = {
                "timestamp": datetime.now().isoformat(),
                "stats": stats,
                "vehicles": cars
            }

            # Save result to DynamoDB
            table.put_item(Item=item)

        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Processed successfully"})
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"message": "Error processing event", "error": str(e)})
        }
