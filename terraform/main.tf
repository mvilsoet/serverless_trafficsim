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

# ECR Repository for Lambda Function Images
resource "aws_ecr_repository" "lambda_repository" {
  name = var.ecr_repository_name
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

# API Gateway for Visualization (State Dump)
resource "aws_apigatewayv2_api" "state_dump_api" {
  name          = "StateDumpAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "state_dump_integration" {
  api_id           = aws_apigatewayv2_api.state_dump_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:stateDump"
}

resource "aws_apigatewayv2_route" "state_dump_route" {
  api_id    = aws_apigatewayv2_api.state_dump_api.id
  route_key = "GET /stateDump"
  target    = "integrations/${aws_apigatewayv2_integration.state_dump_integration.id}"
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "allow_apigateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "stateDump"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.state_dump_api.execution_arn}/*/*"
}
