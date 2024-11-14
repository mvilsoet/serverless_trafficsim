# Traffic Simulation Serverless Version

This project uses Terraform IaC to provision AWS infrastructure and deploy Lambda functions for a traffic simulation system. It uses AWS API Gateway, DynamoDB, SQS, and ECR and Github Actions CI/CD workflows for all necessary components.

## Table of Contents
1. [How to Run](#how-to-run)
2. [Architecture](#architecture)

---

## How to Run

### 1. Fork the Repository
Start by forking this repository to your own GitHub account to enable the CI/CD workflows.

### 2. Set Up Required GitHub Secrets
Add the following secrets to your GitHub repository under **Settings > Secrets and Variables > Actions > New repository secret**:
  
- `AWS_ACCESS_KEY_ID`: Your AWS access key ID.
- `AWS_SECRET_ACCESS_KEY`: Your AWS secret access key.
- `AWS_ACCOUNT_ID`: Your AWS account ID.

### 3. Run the ECR Creation Workflow
So we can automatically assign roles and permissions to the API and Lambda (ECR + Image are dependencies), we must deploy the ECR repo separately in GH Actions and fill it with a dummy image.

- Go to the **Actions** tab in your GitHub repository.
- Select the **"Setup ECR with Placeholder Images"** workflow.
- Manually trigger the workflow by selecting **"Run workflow"**.
  
This will create the ECR repository and push placeholder images to Amazon ECR.

### 4. Run the CI/CD Workflow
With the repository and secrets set up, trigger the CI/CD pipeline to deploy the project infrastructure and Lambda functions.

- Go to **Actions** in your repository.
- Run the **"Deploy Project to AWS Lambda and ECR"** workflow, either on a new push to the `main` branch or by selecting **"Run workflow"**.

This workflow will:
- Provision AWS resources via Terraform.
- Build and push Lambda-compatible Docker images to Amazon ECR.
- Deploy or update Lambda functions with the new container images.

### 5. Send a Test Message with the Python Script
Use the `send_simulation_request.py` script to test the deployed API endpoints.

- Install required libraries:
  ```bash
  pip install requests
  ```
  
- Execute the script with the required parameters:
  ```bash
  python send_simulation_request.py https://<YOUR-API-LINK-ID>.execute-api.us-east-2.amazonaws.com/prod/simulate --method POST --vehicle_count 10 --time_step 2.5
  ```

- Alternatively, retrieve simulation results with a GET request:
  ```bash
  python send_simulation_request.py https://<YOUR-API-LINK-ID>.execute-api.us-east-2.amazonaws.com/prod/results --method GET
  ```

## Architecture
The traffic simulation project is designed with AWS services to handle simulation requests and return results efficiently.

Key components:

- API Gateway: Exposes the simulation and results endpoints for receiving requests.
- SQS Queues: Manages message queues for vehicle trajectory data and traffic light control.
- DynamoDB: Stores simulation results for querying.
- Lambda Functions: Processes simulation requests and retrieves results.
- ECR: Hosts Docker images for Lambda, built from the GitHub CI/CD pipeline.

This high-level architecture supports scalable traffic simulation with AWS, leveraging serverless resources and automated deployment pipelines.
