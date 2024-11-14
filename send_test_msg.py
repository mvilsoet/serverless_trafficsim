import requests
import json
import argparse
from datetime import datetime

def send_simulation_request(api_url, vehicle_count=5, time_step=3.0):
    # Construct the request payload
    payload = {
        "messageType": "SimulationRequest",
        "simulationParams": {
            "time_step": time_step,
            "vehicle_count": vehicle_count
        },
        "requestTime": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    
    # Set up the headers
    headers = {
        "Content-Type": "application/json"
    }
    
    try:
        # Send the POST request
        response = requests.post(
            api_url,
            data=json.dumps(payload),
            headers=headers
        )
        
        # Raise an exception for bad status codes
        response.raise_for_status()
        
        # Print the response
        print(f"Status Code: {response.status_code}")
        print("Response:")
        print(json.dumps(response.json(), indent=2))
        
        return response
        
    except requests.exceptions.RequestException as e:
        print(f"Error occurred: {e}")
        return None

def get_simulation_results(api_url):
    try:
        # Send the GET request
        response = requests.get(api_url)
        
        # Raise an exception for bad status codes
        response.raise_for_status()
        
        # Print the response
        print(f"Status Code: {response.status_code}")
        print("Response:")
        print(json.dumps(response.json(), indent=2))
        
        return response
        
    except requests.exceptions.RequestException as e:
        print(f"Error occurred: {e}")
        return None

if __name__ == "__main__":
    # Set up argument parser
    parser = argparse.ArgumentParser(description="Send simulation request or retrieve simulation results.")
    parser.add_argument(
        "api_url", 
        help="The API endpoint URL to call, e.g., 'https://8o3q4qr9lf.execute-api.us-east-2.amazonaws.com/prod/simulate' or 'https://8o3q4qr9lf.execute-api.us-east-2.amazonaws.com/prod/results'"
    )
    parser.add_argument(
        "--method", 
        choices=["GET", "POST"], 
        required=True, 
        help="HTTP method to use: 'GET' for retrieving results or 'POST' to send a simulation request."
    )
    parser.add_argument(
        "--vehicle_count", 
        type=int, 
        default=5, 
        help="Number of vehicles for the simulation (only used for POST requests)."
    )
    parser.add_argument(
        "--time_step", 
        type=float, 
        default=3.0, 
        help="Time step for the simulation (only used for POST requests)."
    )
    
    # Parse arguments
    args = parser.parse_args()

    # Call the appropriate function based on the method
    if args.method == "POST":
        send_simulation_request(args.api_url, vehicle_count=args.vehicle_count, time_step=args.time_step)
    elif args.method == "GET":
        get_simulation_results(args.api_url)
