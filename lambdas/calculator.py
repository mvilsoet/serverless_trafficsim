import boto3
import json
import os
import random
import logging
from datetime import datetime
from decimal import Decimal
from typing import Dict, List, Any, Tuple

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS resources
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

class ValidationError(Exception):
    """Custom exception for validation errors"""
    pass

def validate_simulation_params(params: Dict[str, Any]) -> Tuple[float, int]:
    """
    Validate simulation parameters and return processed values.
    
    Args:
        params: Dictionary containing simulation parameters
        
    Returns:
        Tuple of (time_step, vehicle_count)
        
    Raises:
        ValidationError: If parameters are invalid
    """
    try:
        time_step = float(params.get("time_step", 1.0))
        vehicle_count = int(params.get("vehicle_count", 5))
        
        if time_step <= 0:
            raise ValidationError("time_step must be positive")
        if vehicle_count <= 0:
            raise ValidationError("vehicle_count must be positive")
            
        return time_step, vehicle_count
    except (ValueError, TypeError) as e:
        raise ValidationError(f"Parameter validation failed: {str(e)}")

def generate_vehicle_data(vehicle_id: int, time_step: float) -> Dict[str, float]:
    """
    Generate simulation data for a single vehicle.
    
    Args:
        vehicle_id: Unique identifier for the vehicle
        time_step: Time step for simulation
        
    Returns:
        Dictionary containing vehicle simulation data
    """
    speed = random.uniform(20, 100)  # Speed in km/h
    distance = speed * time_step     # Distance = speed * time
    
    return {
        "vehicle_id": vehicle_id,
        "speed": float(speed),
        "distance": float(distance),
        "time_step": float(time_step)
    }

def calculate_statistics(vehicles: List[Dict[str, float]], vehicle_count: int) -> Dict[str, float]:
    """
    Calculate aggregate statistics from vehicle data.
    
    Args:
        vehicles: List of vehicle data dictionaries
        vehicle_count: Total number of vehicles
        
    Returns:
        Dictionary containing calculated statistics
    """
    total_distance = sum(v["distance"] for v in vehicles)
    total_speed = sum(v["speed"] for v in vehicles)
    total_time = sum(v["time_step"] for v in vehicles)
    
    return {
        "total_distance": float(total_distance),
        "total_speed": float(total_speed),
        "total_time": float(total_time),
        "average_speed": float(total_speed / vehicle_count),
        "average_time": float(total_time / vehicle_count),
        "average_distance": float(total_distance / vehicle_count)
    }

def run_simulation(time_step: float, vehicle_count: int) -> Dict[str, Any]:
    """
    Run the traffic simulation with given parameters.
    
    Args:
        time_step: Time step for simulation
        vehicle_count: Number of vehicles to simulate
        
    Returns:
        Dictionary containing complete simulation results
    """
    # Generate vehicle data
    vehicles = [
        generate_vehicle_data(i + 1, time_step)
        for i in range(vehicle_count)
    ]
    
    # Calculate statistics
    stats = calculate_statistics(vehicles, vehicle_count)
    
    return {
        "timestamp": datetime.utcnow().isoformat(),
        "simulation_parameters": {
            "time_step": time_step,
            "vehicle_count": vehicle_count
        },
        "statistics": stats,
        "vehicles": vehicles
    }

def save_to_dynamodb(data: Dict[str, Any]) -> None:
    """
    Save simulation results to DynamoDB.
    
    Args:
        data: Simulation results to save
        
    Raises:
        Exception: If save operation fails
    """
    try:
        # Convert all numbers to Decimal for DynamoDB compatibility
        item = json.loads(json.dumps(data), parse_float=Decimal)
        table.put_item(Item=item)
        logger.info(f"Saved simulation results for timestamp: {data['timestamp']}")
    except Exception as e:
        logger.error(f"Error saving to DynamoDB: {str(e)}")
        raise

def process_sqs_message(message_body: str) -> Tuple[float, int]:
    """
    Process and validate an SQS message.
    
    Args:
        message_body: Raw message body string from SQS
        
    Returns:
        Tuple of (time_step, vehicle_count)
        
    Raises:
        ValidationError: If message is invalid
        json.JSONDecodeError: If message is not valid JSON
    """
    # Parse the JSON message
    message = json.loads(message_body)
    
    # Validate message type
    if message.get("messageType") != "SimulationRequest":
        raise ValidationError("Invalid message type")
    
    # Extract and validate simulation parameters
    simulation_params = message.get("simulationParams", {})
    return validate_simulation_params(simulation_params)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function.
    
    Args:
        event: Lambda event data
        context: Lambda context
        
    Returns:
        Dictionary containing response data
        
    Raises:
        Exception: If processing fails
    """
    try:
        logger.info("Received event: %s", json.dumps(event))
        
        # Track processing results
        processed_count = 0
        error_count = 0
        
        # Process each record from the SQS queue
        for record in event['Records']:
            try:
                # Process the message
                time_step, vehicle_count = process_sqs_message(record['body'])
                
                # Run simulation
                simulation_results = run_simulation(time_step, vehicle_count)
                
                # Save results
                save_to_dynamodb(simulation_results)
                
                processed_count += 1
                
            except (json.JSONDecodeError, ValidationError) as e:
                logger.warning(f"Skipping invalid message: {str(e)}")
                error_count += 1
                continue
            except Exception as e:
                logger.error(f"Error processing message: {str(e)}")
                error_count += 1
                continue
        
        # Return summary response
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Processing complete",
                "processed": processed_count,
                "errors": error_count
            })
        }
        
    except Exception as e:
        logger.error(f"Fatal error in lambda_handler: {str(e)}")
        raise

if __name__ == "__main__":
    # Example for local testing
    test_event = {
        "Records": [
            {
                "body": json.dumps({
                    "messageType": "SimulationRequest",
                    "simulationParams": {
                        "time_step": 1.0,
                        "vehicle_count": 5
                    }
                })
            }
        ]
    }
    print(json.dumps(lambda_handler(test_event, None), indent=2))