# Terraform backend configuration (storing state in S3)
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

# Data resource to get the current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for existing ECR Repository
data "aws_ecr_repository" "lambda_repository" {
  name = var.ecr_repository_name
}

# DynamoDB Table for Simulation Data
resource "aws_dynamodb_table" "traffic_simulation" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "entity_id"

  attribute {
    name = "entity_id"
    type = "S"
  }

  attribute {
    name = "entity_type"
    type = "S"
  }

  global_secondary_index {
    name               = "EntityTypeIndex"
    hash_key           = "entity_type"
    projection_type    = "ALL"
  }
}

# SQS Queues
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
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow"
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

# Lambda Functions
resource "aws_lambda_function" "lambda_functions" {
  count         = length(var.lambda_functions)
  function_name = var.lambda_functions[count.index]["name"]
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.lambda_repository.repository_url}:${var.lambda_functions[count.index]["tag"]}"

  # Initial deployment uses the placeholder image
  # Update the code later via AWS CLI in GitHub Actions
}

# API Gateway for stateDump Lambda function
resource "aws_api_gateway_rest_api" "api" {
  name        = "StateDumpAPI"
  description = "API Gateway for StateDump Lambda function"
}

resource "aws_api_gateway_resource" "state_dump" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "stateDump"
}

resource "aws_api_gateway_method" "state_dump_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.state_dump.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.state_dump.id
  http_method             = aws_api_gateway_method.state_dump_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_functions[3].invoke_arn
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_functions[3].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}
