# terraform/main.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure AWS Provider for Primary Region
provider "aws" {
  alias  = "primary"
  region = var.primary_region
}

# Configure AWS Provider for Secondary Region
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "primary" {
  provider = aws.primary
}

data "aws_region" "secondary" {
  provider = aws.secondary
}

# Create DynamoDB table in primary region
resource "aws_dynamodb_table" "primary" {
  provider     = aws.primary
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ItemId"

  attribute {
    name = "ItemId"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = merge(var.tags, {
    Name        = var.dynamodb_table_name
    Region      = var.primary_region
    Environment = var.environment
  })
}

# Create DynamoDB table in secondary region
resource "aws_dynamodb_table" "secondary" {
  provider     = aws.secondary
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ItemId"

  attribute {
    name = "ItemId"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = merge(var.tags, {
    Name        = var.dynamodb_table_name
    Region      = var.secondary_region
    Environment = var.environment
  })
}

# Enable Global Tables
resource "aws_dynamodb_global_table" "main" {
  provider = aws.primary
  name     = var.dynamodb_table_name

  replica {
    region_name = var.primary_region
  }

  replica {
    region_name = var.secondary_region
  }

  depends_on = [
    aws_dynamodb_table.primary,
    aws_dynamodb_table.secondary
  ]
}

# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for Lambda to access DynamoDB
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.project_name}-lambda-dynamodb-policy"
  description = "IAM policy for Lambda to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.primary.arn,
          aws_dynamodb_table.secondary.arn,
          "${aws_dynamodb_table.primary.arn}/*",
          "${aws_dynamodb_table.secondary.arn}/*"
        ]
      }
    ]
  })

  tags = var.tags
}

# Attach policies to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# Create Lambda deployment packages
data "archive_file" "read_function_zip" {
  type        = "zip"
  output_path = "${path.module}/read_function.zip"
  source {
    content  = file("${path.module}/../lambda/read_function.py")
    filename = "lambda_function.py"
  }
}

data "archive_file" "write_function_zip" {
  type        = "zip"
  output_path = "${path.module}/write_function.zip"
  source {
    content  = file("${path.module}/../lambda/write_function.py")
    filename = "lambda_function.py"
  }
}

# Lambda Functions in Primary Region
resource "aws_lambda_function" "read_function_primary" {
  provider         = aws.primary
  filename         = data.archive_file.read_function_zip.output_path
  function_name    = "${var.project_name}-read-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.read_function_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
    }
  }

  tags = merge(var.tags, {
    Name   = "${var.project_name}-read-function-primary"
    Region = var.primary_region
  })
}

resource "aws_lambda_function" "write_function_primary" {
  provider         = aws.primary
  filename         = data.archive_file.write_function_zip.output_path
  function_name    = "${var.project_name}-write-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.write_function_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
    }
  }

  tags = merge(var.tags, {
    Name   = "${var.project_name}-write-function-primary"
    Region = var.primary_region
  })
}

# Lambda Functions in Secondary Region
resource "aws_lambda_function" "read_function_secondary" {
  provider         = aws.secondary
  filename         = data.archive_file.read_function_zip.output_path
  function_name    = "${var.project_name}-read-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.read_function_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
    }
  }

  tags = merge(var.tags, {
    Name   = "${var.project_name}-read-function-secondary"
    Region = var.secondary_region
  })
}

resource "aws_lambda_function" "write_function_secondary" {
  provider         = aws.secondary
  filename         = data.archive_file.write_function_zip.output_path
  function_name    = "${var.project_name}-write-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.write_function_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
    }
  }

  tags = merge(var.tags, {
    Name   = "${var.project_name}-write-function-secondary"
    Region = var.secondary_region
  })
}

# API Gateway REST API - Primary Region
resource "aws_api_gateway_rest_api" "primary" {
  provider    = aws.primary
  name        = "${var.project_name}-api"
  description = "High Availability API - Primary Region"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(var.tags, {
    Name   = "${var.project_name}-api-primary"
    Region = var.primary_region
  })
}

# API Gateway REST API - Secondary Region
resource "aws_api_gateway_rest_api" "secondary" {
  provider    = aws.secondary
  name        = "${var.project_name}-api"
  description = "High Availability API - Secondary Region"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(var.tags, {
    Name   = "${var.project_name}-api-secondary"
    Region = var.secondary_region
  })
}

# API Gateway Resources and Methods - Primary Region
resource "aws_api_gateway_resource" "read_primary" {
  provider    = aws.primary
  rest_api_id = aws_api_gateway_rest_api.primary.id
  parent_id   = aws_api_gateway_rest_api.primary.root_resource_id
  path_part   = "read"
}

resource "aws_api_gateway_resource" "write_primary" {
  provider    = aws.primary
  rest_api_id = aws_api_gateway_rest_api.primary.id
  parent_id   = aws_api_gateway_rest_api.primary.root_resource_id
  path_part   = "write"
}

resource "aws_api_gateway_method" "read_get_primary" {
  provider      = aws.primary
  rest_api_id   = aws_api_gateway_rest_api.primary.id
  resource_id   = aws_api_gateway_resource.read_primary.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "write_post_primary" {
  provider      = aws.primary
  rest_api_id   = aws_api_gateway_rest_api.primary.id
  resource_id   = aws_api_gateway_resource.write_primary.id
  http_method   = "POST"
  authorization = "NONE"
  request_parameters = {
    "method.request.header.Content-Type" = true
  }
}

# API Gateway Integrations - Primary Region
resource "aws_api_gateway_integration" "read_integration_primary" {
  provider                = aws.primary
  rest_api_id             = aws_api_gateway_rest_api.primary.id
  resource_id             = aws_api_gateway_resource.read_primary.id
  http_method             = aws_api_gateway_method.read_get_primary.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.read_function_primary.invoke_arn
}



resource "aws_api_gateway_integration" "write_integration_primary" {
  provider                = aws.primary
  rest_api_id             = aws_api_gateway_rest_api.primary.id
  resource_id             = aws_api_gateway_resource.write_primary.id
  http_method             = aws_api_gateway_method.write_post_primary.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.write_function_primary.invoke_arn

  request_parameters = {
    "integration.request.header.Content-Type" = "method.request.header.Content-Type"
  }
}

# API Gateway Resources and Methods - Secondary Region
resource "aws_api_gateway_resource" "read_secondary" {
  provider    = aws.secondary
  rest_api_id = aws_api_gateway_rest_api.secondary.id
  parent_id   = aws_api_gateway_rest_api.secondary.root_resource_id
  path_part   = "read"
}

resource "aws_api_gateway_resource" "write_secondary" {
  provider    = aws.secondary
  rest_api_id = aws_api_gateway_rest_api.secondary.id
  parent_id   = aws_api_gateway_rest_api.secondary.root_resource_id
  path_part   = "write"
}

resource "aws_api_gateway_method" "read_get_secondary" {
  provider      = aws.secondary
  rest_api_id   = aws_api_gateway_rest_api.secondary.id
  resource_id   = aws_api_gateway_resource.read_secondary.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "write_post_secondary" {
  provider      = aws.secondary
  rest_api_id   = aws_api_gateway_rest_api.secondary.id
  resource_id   = aws_api_gateway_resource.write_secondary.id
  http_method   = "POST"
  authorization = "NONE"

  request_parameters = {
    "method.request.header.Content-Type" = true
  }
}

# API Gateway Integrations - Secondary Region
resource "aws_api_gateway_integration" "read_integration_secondary" {
  provider                = aws.secondary
  rest_api_id             = aws_api_gateway_rest_api.secondary.id
  resource_id             = aws_api_gateway_resource.read_secondary.id
  http_method             = aws_api_gateway_method.read_get_secondary.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.read_function_secondary.invoke_arn
}

resource "aws_api_gateway_integration" "write_integration_secondary" {
  provider                = aws.secondary
  rest_api_id             = aws_api_gateway_rest_api.secondary.id
  resource_id             = aws_api_gateway_resource.write_secondary.id
  http_method             = aws_api_gateway_method.write_post_secondary.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.write_function_secondary.invoke_arn
  request_parameters = {
    "integration.request.header.Content-Type" = "method.request.header.Content-Type"
  }
}

# Lambda permissions for API Gateway - Primary Region
resource "aws_lambda_permission" "read_permission_primary" {
  provider      = aws.primary
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.read_function_primary.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.primary.execution_arn}/*/*"
}

resource "aws_lambda_permission" "write_permission_primary" {
  provider      = aws.primary
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.write_function_primary.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.primary.execution_arn}/*/*"
}

# Lambda permissions for API Gateway - Secondary Region
resource "aws_lambda_permission" "read_permission_secondary" {
  provider      = aws.secondary
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.read_function_secondary.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.secondary.execution_arn}/*/*"
}

resource "aws_lambda_permission" "write_permission_secondary" {
  provider      = aws.secondary
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.write_function_secondary.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.secondary.execution_arn}/*/*"
}

# CORS configuration for API Gateway - Primary Region
resource "aws_api_gateway_method" "cors_read_primary" {
  provider      = aws.primary
  rest_api_id   = aws_api_gateway_rest_api.primary.id
  resource_id   = aws_api_gateway_resource.read_primary.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "cors_write_primary" {
  provider      = aws.primary
  rest_api_id   = aws_api_gateway_rest_api.primary.id
  resource_id   = aws_api_gateway_resource.write_primary.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cors_read_integration_primary" {
  provider    = aws.primary
  rest_api_id = aws_api_gateway_rest_api.primary.id
  resource_id = aws_api_gateway_resource.read_primary.id
  http_method = aws_api_gateway_method.cors_read_primary.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration" "cors_write_integration_primary" {
  provider    = aws.primary
  rest_api_id = aws_api_gateway_rest_api.primary.id
  resource_id = aws_api_gateway_resource.write_primary.id
  http_method = aws_api_gateway_method.cors_write_primary.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# CORS Method Responses - Primary Region
resource "aws_api_gateway_method_response" "cors_read_response_primary" {
  provider    = aws.primary
  rest_api_id = aws_api_gateway_rest_api.primary.id
  resource_id = aws_api_gateway_resource.read_primary.id
  http_method = aws_api_gateway_method.cors_read_primary.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_method_response" "cors_write_response_primary" {
  provider    = aws.primary
  rest_api_id = aws_api_gateway_rest_api.primary.id
  resource_id = aws_api_gateway_resource.write_primary.id
  http_method = aws_api_gateway_method.cors_write_primary.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Add to your existing CORS configuration in primary region
resource "aws_api_gateway_method_response" "write_post_response_primary" {
  provider    = aws.primary
  rest_api_id = aws_api_gateway_rest_api.primary.id
  resource_id = aws_api_gateway_resource.write_primary.id
  http_method = aws_api_gateway_method.write_post_primary.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "write_integration_response_primary" {
  provider    = aws.primary
  rest_api_id = aws_api_gateway_rest_api.primary.id
  resource_id = aws_api_gateway_resource.write_primary.id
  http_method = aws_api_gateway_method.write_post_primary.http_method
  status_code = aws_api_gateway_method_response.write_post_response_primary.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Requested-With'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# CORS Integration Responses - Primary Region
resource "aws_api_gateway_integration_response" "cors_read_integration_response_primary" {
  provider    = aws.primary
  rest_api_id = aws_api_gateway_rest_api.primary.id
  resource_id = aws_api_gateway_resource.read_primary.id
  http_method = aws_api_gateway_method.cors_read_primary.http_method
  status_code = aws_api_gateway_method_response.cors_read_response_primary.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_integration_response" "cors_write_integration_response_primary" {
  provider    = aws.primary
  rest_api_id = aws_api_gateway_rest_api.primary.id
  resource_id = aws_api_gateway_resource.write_primary.id
  http_method = aws_api_gateway_method.cors_write_primary.http_method
  status_code = aws_api_gateway_method_response.cors_write_response_primary.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Similar CORS configuration for Secondary Region
resource "aws_api_gateway_method" "cors_read_secondary" {
  provider      = aws.secondary
  rest_api_id   = aws_api_gateway_rest_api.secondary.id
  resource_id   = aws_api_gateway_resource.read_secondary.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "cors_write_secondary" {
  provider      = aws.secondary
  rest_api_id   = aws_api_gateway_rest_api.secondary.id
  resource_id   = aws_api_gateway_resource.write_secondary.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cors_read_integration_secondary" {
  provider    = aws.secondary
  rest_api_id = aws_api_gateway_rest_api.secondary.id
  resource_id = aws_api_gateway_resource.read_secondary.id
  http_method = aws_api_gateway_method.cors_read_secondary.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration" "cors_write_integration_secondary" {
  provider    = aws.secondary
  rest_api_id = aws_api_gateway_rest_api.secondary.id
  resource_id = aws_api_gateway_resource.write_secondary.id
  http_method = aws_api_gateway_method.cors_write_secondary.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Add to your existing CORS configuration in secondary region
resource "aws_api_gateway_method_response" "write_post_response_secondary" {
  provider    = aws.secondary
  rest_api_id = aws_api_gateway_rest_api.secondary.id
  resource_id = aws_api_gateway_resource.write_secondary.id
  http_method = aws_api_gateway_method.write_post_secondary.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "write_integration_response_secondary" {
  provider    = aws.secondary
  rest_api_id = aws_api_gateway_rest_api.secondary.id
  resource_id = aws_api_gateway_resource.write_secondary.id
  http_method = aws_api_gateway_method.write_post_secondary.http_method
  status_code = aws_api_gateway_method_response.write_post_response_secondary.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Requested-With'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}
# Deploy API Gateway
resource "aws_api_gateway_deployment" "primary" {
  provider = aws.primary
  depends_on = [
    aws_api_gateway_integration.read_integration_primary,
    aws_api_gateway_integration.write_integration_primary,
    aws_api_gateway_integration.cors_read_integration_primary,
    aws_api_gateway_integration_response.write_integration_response_primary,
    aws_api_gateway_integration.cors_write_integration_primary,
    aws_api_gateway_integration_response.cors_read_integration_response_primary,
    aws_api_gateway_integration_response.cors_write_integration_response_primary,
  ]

  rest_api_id = aws_api_gateway_rest_api.primary.id
  stage_name  = var.api_stage_name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_deployment" "secondary" {
  provider = aws.secondary
  depends_on = [
    aws_api_gateway_integration.read_integration_secondary,
    aws_api_gateway_integration.write_integration_secondary,
    aws_api_gateway_integration.cors_read_integration_secondary,
    aws_api_gateway_integration.cors_write_integration_secondary,
    aws_api_gateway_integration_response.write_integration_response_secondary,
  ]

  rest_api_id = aws_api_gateway_rest_api.secondary.id
  stage_name  = var.api_stage_name

  lifecycle {
    create_before_destroy = true
  }
}

# ACM Certificate for Primary Region
resource "aws_acm_certificate" "primary" {
  provider          = aws.primary
  domain_name       = "api.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "api.${var.domain_name}-primary"
  })
}

# ACM Certificate for Secondary Region
resource "aws_acm_certificate" "secondary" {
  provider          = aws.secondary
  domain_name       = "api.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "api.${var.domain_name}-secondary"
  })
}

# DNS validation records for primary certificate
resource "aws_route53_record" "cert_validation_primary" {
  for_each = {
    for dvo in aws_acm_certificate.primary.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# DNS validation records for secondary certificate
resource "aws_route53_record" "cert_validation_secondary" {
  for_each = {
    for dvo in aws_acm_certificate.secondary.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# Certificate validation for primary region
resource "aws_acm_certificate_validation" "primary" {
  provider                = aws.primary
  certificate_arn         = aws_acm_certificate.primary.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation_primary : record.fqdn]

  timeouts {
    create = "5m"
  }
}

# Certificate validation for secondary region
resource "aws_acm_certificate_validation" "secondary" {
  provider                = aws.secondary
  certificate_arn         = aws_acm_certificate.secondary.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation_secondary : record.fqdn]

  timeouts {
    create = "5m"
  }
}

# Custom Domain for API Gateway - Primary Region
resource "aws_api_gateway_domain_name" "primary" {
  provider                 = aws.primary
  domain_name              = "api.${var.domain_name}"
  regional_certificate_arn = aws_acm_certificate_validation.primary.certificate_arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  depends_on = [aws_acm_certificate_validation.primary]

  tags = merge(var.tags, {
    Name = "api.${var.domain_name}-primary"
  })
}

# Custom Domain for API Gateway - Secondary Region
resource "aws_api_gateway_domain_name" "secondary" {
  provider                 = aws.secondary
  domain_name              = "api.${var.domain_name}"
  regional_certificate_arn = aws_acm_certificate_validation.secondary.certificate_arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  depends_on = [aws_acm_certificate_validation.secondary]

  tags = merge(var.tags, {
    Name = "api.${var.domain_name}-secondary"
  })
}

# API Gateway Base Path Mapping - Primary Region
resource "aws_api_gateway_base_path_mapping" "primary" {
  provider    = aws.primary
  api_id      = aws_api_gateway_rest_api.primary.id
  stage_name  = aws_api_gateway_deployment.primary.stage_name
  domain_name = aws_api_gateway_domain_name.primary.domain_name
  base_path   = "" # Explicitly set to empty (root path)
}

# API Gateway Base Path Mapping - Secondary Region
resource "aws_api_gateway_base_path_mapping" "secondary" {
  provider    = aws.secondary
  api_id      = aws_api_gateway_rest_api.secondary.id
  stage_name  = aws_api_gateway_deployment.secondary.stage_name
  domain_name = aws_api_gateway_domain_name.secondary.domain_name
}

# Route 53 Health Checks
resource "aws_route53_health_check" "primary" {
  fqdn              = aws_api_gateway_domain_name.primary.regional_domain_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/${var.api_stage_name}/read"
  failure_threshold = "3"
  request_interval  = "30"
  measure_latency   = true

  tags = merge(var.tags, {
    Name = "Primary API Health Check"
  })
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = aws_api_gateway_domain_name.secondary.regional_domain_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/${var.api_stage_name}/read"
  failure_threshold = "3"
  request_interval  = "30"
  measure_latency   = true

  tags = merge(var.tags, {
    Name = "Secondary API Health Check"
  })
}

# # Route 53 Hosted Zone (assuming it exists)
# data "aws_route53_zone" "main" {
#   name         = var.domain_name
#   private_zone = false
# }

# Route 53 Records for Failover
resource "aws_route53_record" "primary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = aws_api_gateway_domain_name.primary.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.primary.regional_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  health_check_id = aws_route53_health_check.secondary.id

  alias {
    name                   = aws_api_gateway_domain_name.secondary.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.secondary.regional_zone_id
    evaluate_target_health = true
  }
}

# S3 Bucket for Frontend Website
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-${random_id.bucket_suffix.hex}"

  tags = merge(var.tags, {
    Name = "${var.project_name}-frontend"
  })
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket     = aws_s3_bucket.frontend.id
  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })
}

# Upload the frontend website
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "${path.module}/../frontend/index.html"
  etag         = filemd5("${path.module}/../frontend/index.html") #/../lambda/read_function.py
  content_type = "text/html"
}

# # CloudFront Distribution for Frontend (Optional but recommended)
# resource "aws_cloudfront_distribution" "frontend" {
#   origin {
#     domain_name = aws_s3_bucket_website_configuration.frontend.website_endpoint
#     origin_id   = "S3-${aws_s3_bucket.frontend.id}"

#     custom_origin_config {
#       http_port              = 80
#       https_port             = 443
#       origin_protocol_policy = "http-only"
#       origin_ssl_protocols   = ["TLSv1.2"]
#     }
#   }

#   enabled             = true
#   is_ipv6_enabled     = true
#   default_root_object = "index.html"

#   default_cache_behavior {
#     allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
#     cached_methods   = ["GET", "HEAD"]
#     target_origin_id = "S3-${aws_s3_bucket.frontend.id}"

#     forwarded_values {
#       query_string = false

#       cookies {
#         forward = "none"
#       }
#     }

#     viewer_protocol_policy = "redirect-to-https"
#     min_ttl                = 0
#     default_ttl            = 3600
#     max_ttl                = 86400
#   }

#   restrictions {
#     geo_restriction {
#       restriction_type = "none"
#     }
#   }

#   viewer_certificate {
#     cloudfront_default_certificate = true
#   }

#   tags = merge(var.tags, {
#     Name = "${var.project_name}-frontend-cdn"
#   })
# }
