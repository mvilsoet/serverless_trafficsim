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
  default = "lambda_repository"
}

variable "lambda_functions" {
  type = list(object({
    name = string
    tag  = string
  }))
  default = [
    { name = "calculator", tag = "latest" },
    { name = "results", tag = "latest" }
  ]
}
