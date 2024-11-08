variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-2"
}

variable "dynamodb_table_name" {
  description = "The name of the DynamoDB table for traffic simulation data."
  type        = string
  default     = "TrafficSimulation"
}

variable "ecr_repository_name" {
  description = "The name of the existing ECR repository for Lambda function images."
  type        = string
  default     = "traffic-simulation-lambda-repo"
}

variable "lambda_functions" {
  description = "List of Lambda functions to create."
  type = list(object({
    name = string
    tag  = string
  }))
  default = [
    { name = "trajectory", tag = "trajectory" },
    { name = "lights", tag = "lights" },
    { name = "roadValidation", tag = "roadValidation" },
    { name = "stateDump", tag = "stateDump" },
  ]
}
