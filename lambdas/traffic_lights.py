import json
import boto3
import datetime

sqs = boto3.client('sqs')
dynamodb = boto3.resource('dynamodb')

# Define the DynamoDB table to store traffic light states
TRAFFIC_LIGHT_STATE_TABLE = "TrafficLightStates"

def lambda_handler(event, context):
    """
    AWS Lambda handler for processing traffic light control messages from SQS.
    
    Args:
        event (dict): The event dictionary containing SQS messages.
        context (LambdaContext): The runtime information of the Lambda function.
    """
    
    table = dynamodb.Table(TRAFFIC_LIGHT_STATE_TABLE)
    
    # Process each message in the SQS event
    for record in event['Records']:
        try:
            message_body = json.loads(record['body'])
            
            # Extract traffic light control parameters
            message_type = message_body.get("messageType")
            traffic_light_id = message_body.get("trafficLightId")
            action = message_body.get("action")  # Actions like "TURN_GREEN", "TURN_RED", "BLINK_YELLOW"
            timestamp = datetime.datetime.utcnow().isoformat() + "Z"

            # Log each received message with a timestamp
            print(f"[{timestamp}] Received message for Traffic Light ID {traffic_light_id}: Action - {action}")
            
            # Handle only TrafficLightControl messages
            if message_type == "TrafficLightControl":
                # Log and simulate handling of each traffic light action
                if action == "TURN_GREEN":
                    print(f"Setting Traffic Light {traffic_light_id} to GREEN.")
                    update_traffic_light_state(table, traffic_light_id, "GREEN", timestamp)

                elif action == "TURN_RED":
                    print(f"Setting Traffic Light {traffic_light_id} to RED.")
                    update_traffic_light_state(table, traffic_light_id, "RED", timestamp)

                elif action == "BLINK_YELLOW":
                    print(f"Setting Traffic Light {traffic_light_id} to BLINK YELLOW.")
                    update_traffic_light_state(table, traffic_light_id, "BLINK_YELLOW", timestamp)

                else:
                    print(f"Unknown action '{action}' for Traffic Light {traffic_light_id}. Logging as unhandled.")
                    log_unhandled_action(traffic_light_id, action, timestamp)

                print("Traffic light action processed successfully.")
            
            else:
                print(f"Received non-traffic control message type: {message_type}")
        
        except Exception as e:
            print(f"Error processing message: {e}")
            print(f"Message body: {record['body']}")
    
    # Success response
    return {
        'statusCode': 200,
        'body': json.dumps('Traffic light handling completed')
    }

def update_traffic_light_state(table, traffic_light_id, state, timestamp):
    """
    Updates the traffic light state in DynamoDB.
    
    Args:
        table (Table): The DynamoDB table resource.
        traffic_light_id (str): The ID of the traffic light.
        state (str): The new state of the traffic light (e.g., "GREEN", "RED").
        timestamp (str): The timestamp of the state change.
    """
    response = table.put_item(
        Item={
            "traffic_light_id": traffic_light_id,
            "state": state,
            "last_updated": timestamp
        }
    )
    print(f"Traffic light {traffic_light_id} state updated to {state} in DynamoDB at {timestamp}.")

def log_unhandled_action(traffic_light_id, action, timestamp):
    """
    Logs an unhandled action for a traffic light.
    
    Args:
        traffic_light_id (str): The ID of the traffic light.
        action (str): The unhandled action.
        timestamp (str): The timestamp of the unhandled action.
    """
    print(f"[{timestamp}] Unhandled action for Traffic Light {traffic_light_id}: {action}. This requires attention.")
