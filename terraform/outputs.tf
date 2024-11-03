output "ecr_repository_name" {
  value       = aws_ecr_repository.lambda_repository.name
  description = "The name of the ECR repository for Lambda functions."
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.lambda_repository.repository_url
  description = "The full URL of the ECR repository for Lambda function images."
}

output "state_dump_api_endpoint" {
  value       = aws_apigatewayv2_api.state_dump_api.api_endpoint
  description = "The API Gateway endpoint for the stateDump Lambda function."
}
