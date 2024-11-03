provider "aws" {
  region = "us-west-2"
}

resource "aws_dynamodb_table" "traffic_simulation" {
  name           = "TrafficSimulation"
  hash_key       = "entity_id"
  billing_mode   = "PAY_PER_REQUEST"

  attribute {
    name = "entity_id"
    type = "S"
  }

  global_secondary_index {
    name               = "EntityTypeIndex"
    hash_key           = "entity_type"
    projection_type    = "ALL"
  }
}

resource "aws_sqs_queue" "vehicle_trajectory_queue" {
  name = "VehicleTrajectoryQueue"
}

resource "aws_sqs_queue" "traffic_light_queue" {
  name = "TrafficLightQueue"
}

# Create IAM role and policy for Lambda
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

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda functions
resource "aws_lambda_function" "vehicle_trajectory" {
  function_name = "VehicleTrajectoryLambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.8"
  environment {
    variables = {
      DYNAMODB_TABLE               = aws_dynamodb_table.traffic_simulation.name
      VEHICLE_TRAJECTORY_QUEUE     = aws_sqs_queue.vehicle_trajectory_queue.id
    }
  }
}

# API Gateway
resource "aws_apigatewayv2_api" "traffic_simulation_api" {
  name          = "TrafficSimulationAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "visualization_integration" {
  api_id           = aws_apigatewayv2_api.traffic_simulation_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.visualization.invoke_arn
}

resource "aws_apigatewayv2_route" "visualization_route" {
  api_id    = aws_apigatewayv2_api.traffic_simulation_api.id
  route_key = "GET /visualize"
  target    = "integrations/${aws_apigatewayv2_integration.visualization_integration.id}"
}

resource "aws_lambda_permission" "allow_apigateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visualization.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.traffic_simulation_api.execution_arn}/*/*"
}
