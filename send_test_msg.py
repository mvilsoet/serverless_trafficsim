import requests
import json
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

if __name__ == "__main__":
    # API endpoint URL
    API_URL = "https://8o3q4qr9lf.execute-api.us-east-2.amazonaws.com/prod/simulate"
    
    # Send the request
    send_simulation_request(API_URL)