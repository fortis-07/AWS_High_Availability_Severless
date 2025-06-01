# terraform/terraform.tfvars
# Customize these values for your deployment
project_name = "ha-serverless-app"
environment  = "prod"

# AWS Regions
primary_region   = "us-east-1"
secondary_region = "us-west-2"

# Your domain name
domain_name = "ponmile.com.ng"

# DynamoDB Table Name
dynamodb_table_name = "HighAvailabilityTable"

# API Gateway Stage
api_stage_name = "prod"

# Resource Tags
tags = {
  Project     = "HighAvailabilityApp"
  Environment = "Production"
  ManagedBy   = "Terraform"
  Owner       = "DevOps Team"
}
