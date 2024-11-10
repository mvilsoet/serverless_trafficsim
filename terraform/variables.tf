variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "dynamodb_table_name" {
  type    = string
  default = "TrafficSimulation"
}

variable "ecr_repository_name" {
  type    = string
  default = "traffic-simulation-lambda-repo"
}

variable "lambda_functions" {
  type = list(object({
    name = string
    tag  = string
  }))
  default = [
    { name = "calculator", tag = "calculator" },
    { name = "results", tag = "results" }
  ]
}
