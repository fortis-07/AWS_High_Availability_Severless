# terraform/outputs.tf
output "primary_api_gateway_url" {
  description = "URL of the primary API Gateway"
  value       = "https://${aws_api_gateway_rest_api.primary.id}.execute-api.${var.primary_region}.amazonaws.com/${var.api_stage_name}"
}

output "secondary_api_gateway_url" {
  description = "URL of the secondary API Gateway"
  value       = "https://${aws_api_gateway_rest_api.secondary.id}.execute-api.${var.secondary_region}.amazonaws.com/${var.api_stage_name}"
}

output "custom_domain_url" {
  description = "Custom domain URL for the API"
  value       = "https://api.${var.domain_name}"
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.primary.name
}

output "primary_region" {
  description = "Primary AWS region"
  value       = var.primary_region
}

output "secondary_region" {
  description = "Secondary AWS region"
  value       = var.secondary_region
}

output "frontend_s3_bucket" {
  description = "S3 bucket name for frontend"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_website_url" {
  description = "Frontend website URL"
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}

# output "cloudfront_distribution_url" {
#   description = "CloudFront distribution URL"
#   value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
# }

output "route53_health_check_primary" {
  description = "Primary health check ID"
  value       = aws_route53_health_check.primary.id
}

output "route53_health_check_secondary" {
  description = "Secondary health check ID"
  value       = aws_route53_health_check.secondary.id
}

output "acm_certificate_primary_arn" {
  description = "Primary ACM certificate ARN"
  value       = aws_acm_certificate.primary.arn
}

output "acm_certificate_secondary_arn" {
  description = "Secondary ACM certificate ARN"
  value       = aws_acm_certificate.secondary.arn
}
