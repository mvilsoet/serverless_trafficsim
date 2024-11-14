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

# IAM Role for API Gateway to Access SQS and DynamoDB
resource "aws_iam_role" "api_gateway_role" {
  name = "ApiGatewayRole"
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

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "ApiGatewayPolicy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "sqs:SendMessage",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        "Resource" : [
          aws_sqs_queue.vehicle_trajectory_queue.arn,
          aws_sqs_queue.traffic_light_queue.arn,
          aws_dynamodb_table.traffic_simulation.arn
        ]
      }
    ]
  })
}

# Lambda Functions for Processing Simulation Requests
resource "aws_lambda_function" "lambda_functions" {
  count         = 2
  function_name = var.lambda_functions[count.index]["name"]
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.traffic-simulation-lambda-repo.repository_url}:${var.lambda_functions[count.index]["tag"]}"
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

# API Gateway Resources
resource "aws_api_gateway_rest_api" "api" {
  name        = "SimulationAPI"
  description = "API Gateway for Simulation Lambda functions"
}

resource "aws_api_gateway_resource" "simulation" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "simulate"
}

resource "aws_api_gateway_resource" "results" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "results"
}

# API Methods
resource "aws_api_gateway_method" "simulate_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.simulation.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "results_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.results.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway Integrations
resource "aws_api_gateway_integration" "simulate_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.simulation.id
  http_method             = aws_api_gateway_method.simulate_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.aws_region}:sqs:action/SendMessage"
  credentials             = aws_iam_role.api_gateway_role.arn

  request_parameters = {
    "integration.request.querystring.Action"    = "'SendMessage'"
    "integration.request.querystring.QueueUrl"  = "'https://sqs.${var.aws_region}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.vehicle_trajectory_queue.name}'"
    "integration.request.header.Content-Type"   = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = <<EOF
#set($body = $input.json('$'))
Action=SendMessage&QueueUrl=$util.urlEncode($integration.request.querystring.QueueUrl)&MessageBody=$util.urlEncode($input.body)
EOF
  }
}

resource "aws_api_gateway_integration" "results_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.results.id
  http_method             = aws_api_gateway_method.results_get.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.aws_region}:dynamodb:action/Query"
  credentials             = aws_iam_role.api_gateway_role.arn

  request_templates = {
    "application/json" = <<EOF
{
    "TableName": "${aws_dynamodb_table.traffic_simulation.name}",
    "Limit": 10,
    "ScanIndexForward": false
}
EOF
  }
}

# Method Responses
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

resource "aws_api_gateway_method_response" "results_response_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.results.id
  http_method = aws_api_gateway_method.results_get.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Integration Responses
resource "aws_api_gateway_integration_response" "simulate_integration_response" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.simulation.id
  http_method       = aws_api_gateway_method.simulate_post.http_method
  status_code       = aws_api_gateway_method_response.simulate_response_200.status_code
  selection_pattern = "^2[0-9][0-9]"

  response_templates = {
    "application/json" = <<EOF
{
    "message": "Message sent to queue successfully"
}
EOF
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.simulate_integration]
}

resource "aws_api_gateway_integration_response" "results_integration_response" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.results.id
  http_method       = aws_api_gateway_method.results_get.http_method
  status_code       = aws_api_gateway_method_response.results_response_200.status_code
  selection_pattern = "^2[0-9][0-9]"

  response_templates = {
    "application/json" = <<EOF
#set($inputRoot = $input.path('$'))
{
    "results": $input.json('$.Items')
}
EOF
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.results_integration]
}

# CORS Support
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

resource "aws_api_gateway_integration_response" "simulate_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.simulation.id
  http_method = aws_api_gateway_method.simulate_options.http_method
  status_code = aws_api_gateway_method_response.simulate_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.simulate_options]
}

# Deploy the API Gateway
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.simulation.id,
      aws_api_gateway_resource.results.id,
      aws_api_gateway_method.simulate_post.id,
      aws_api_gateway_method.results_get.id,
      aws_api_gateway_integration.simulate_integration.id,
      aws_api_gateway_integration.results_integration.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}
