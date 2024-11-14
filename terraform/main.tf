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

# Data resources
data "aws_caller_identity" "current" {}

data "aws_ecr_repository" "traffic-simulation-lambda-repo" {
  name = var.ecr_repository_name
}

# DynamoDB Table
resource "aws_dynamodb_table" "traffic_simulation" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "timestamp"

  attribute {
    name = "timestamp"
    type = "S"
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

# IAM Policies for Lambda
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
  count         = 2
  function_name = var.lambda_functions[count.index]["name"]
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.traffic-simulation-lambda-repo.repository_url}:${var.lambda_functions[count.index]["tag"]}"
}

# Event Source Mappings for Lambda
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
