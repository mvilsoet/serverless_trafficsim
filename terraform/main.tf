terraform {
  backend "s3" {
    bucket = "mvilsoet-bucket"
    key    = "terraform.tfstate"
    region = "us-east-2"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data resources to retrieve existing AWS information
data "aws_caller_identity" "current" {}

data "aws_ecr_repository" "traffic-simulation-lambda-repo" {
  name = var.ecr_repository_name
}

# DynamoDB Table for Simulation Data
resource "aws_dynamodb_table" "traffic_simulation" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "timestamp"

  attribute {
    name = "timestamp"
    type = "S"
  }
}

# SQS Queues for Simulation Requests and Traffic Light Control
resource "aws_sqs_queue" "vehicle_trajectory_queue" {
  name = "VehicleTrajectoryQueue"
}

resource "aws_sqs_queue" "traffic_light_queue" {
  name = "TrafficLightQueue"
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_exec_role" {
  name = "LambdaExecutionRole"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Effect" : "Allow"
      }
    ]
  })
}

# IAM Policies for Lambda Access to DynamoDB, SQS, and CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_logs_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM Role and Policy for API Gateway to Access SQS
resource "aws_iam_role" "api_gateway_sqs_role" {
  name = "ApiGatewaySqsRole"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "Service" : "apigateway.amazonaws.com"
        },
        "Effect" : "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_sqs_policy" {
  role = aws_iam_role.api_gateway_sqs_role.name
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : ["sqs:SendMessage"],
        "Resource" : [
          aws_sqs_queue.vehicle_trajectory_queue.arn,
          aws_sqs_queue.traffic_light_queue.arn
        ]
      }
    ]
  })
}

# Lambda Function for Processing Simulation Requests
resource "aws_lambda_function" "lambda_functions" {
  count         = 2
  function_name = var.lambda_functions[count.index]["name"]
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.traffic-simulation-lambda-repo.repository_url}:${var.lambda_functions[count.index]["tag"]}"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.traffic_simulation.name
    }
  }
}

# Event Source Mappings for SQS Queues to Trigger Lambda
resource "aws_lambda_event_source_mapping" "vehicle_trajectory_trigger" {
  event_source_arn = aws_sqs_queue.vehicle_trajectory_queue.arn
  function_name    = aws_lambda_function.lambda_functions[0].function_name
  batch_size       = 10
  enabled          = true
}

resource "aws_lambda_event_source_mapping" "traffic_light_trigger" {
  event_source_arn = aws_sqs_queue.traffic_light_queue.arn
  function_name    = aws_lambda_function.lambda_functions[1].function_name
  batch_size       = 10
  enabled          = true
}

# API Gateway Resources and Methods
resource "aws_api_gateway_rest_api" "api" {
  name        = "SimulationAPI"
  description = "API Gateway for Simulation Lambda functions"
}

resource "aws_api_gateway_resource" "simulation" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "simulate"
}

resource "aws_api_gateway_method" "simulate_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.simulation.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration for the Simulation Endpoint
resource "aws_api_gateway_integration" "simulate_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.simulation.id
  http_method             = aws_api_gateway_method.simulate_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.aws_region}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.vehicle_trajectory_queue.name}"
  credentials             = aws_iam_role.api_gateway_sqs_role.arn

  request_templates = {
    "application/json" = <<EOF
Action=SendMessage&MessageBody=$input.body
EOF
  }
}

# Method Response
resource "aws_api_gateway_method_response" "simulate_response_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.simulation.id
  http_method = aws_api_gateway_method.simulate_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Integration Response
resource "aws_api_gateway_integration_response" "simulate_integration_response" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.simulation.id
  http_method       = aws_api_gateway_method.simulate_post.http_method
  status_code       = aws_api_gateway_method_response.simulate_response_200.status_code
  selection_pattern = "^2[0-9][0-9]"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  response_templates = {
    "application/json" = <<EOF
{
  "message": "Request accepted"
}
EOF
  }

  depends_on = [aws_api_gateway_integration.simulate_integration]
}

# Add CORS support
resource "aws_api_gateway_method" "simulate_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.simulation.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "simulate_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.simulation.id
  http_method = aws_api_gateway_method.simulate_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "simulate_options_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.simulation.id
  http_method = aws_api_gateway_method.simulate_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "simulate_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.simulation.id
  http_method = aws_api_gateway_method.simulate_options.http_method
  status_code = aws_api_gateway_method_response.simulate_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.simulate_options]
}

# Deploy the API Gateway
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.simulate_integration,
    aws_api_gateway_integration.simulate_options,
    aws_api_gateway_integration_response.simulate_integration_response,
    aws_api_gateway_integration_response.simulate_options
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
}

# Output the API Gateway URL
output "api_url" {
  value = "${aws_api_gateway_deployment.api_deployment.invoke_url}/simulate"
}