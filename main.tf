terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

###############################################################################
# ZIP PACKAGE
###############################################################################

# Luo zip Terraformilla automaattisesti aina kun koodi muuttuu
data "archive_file" "xhtml_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/xhtmlToMd.zip"
}

###############################################################################
# IAM ROLE for Lambda
###############################################################################

resource "aws_iam_role" "lambda_role" {
  name = "xhtml-to-md-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Lambda Basic Execution Role (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

###############################################################################
# LAMBDA FUNCTION
###############################################################################

resource "aws_lambda_function" "xhtml_to_md" {
  function_name    = "xhtmlToMarkdown"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  timeout          = 15
  memory_size      = 256

  filename         = data.archive_file.xhtml_zip.output_path
  source_code_hash = data.archive_file.xhtml_zip.output_base64sha256
}

###############################################################################
# API GATEWAY HTTP API
###############################################################################

resource "aws_apigatewayv2_api" "api" {
  name          = "xhtml-to-md-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "integration" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.xhtml_to_md.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /convert"
  target    = "integrations/${aws_apigatewayv2_integration.integration.id}"
}

resource "aws_apigatewayv2_stage" "stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

###############################################################################
# LAMBDA PERMISSION FOR API GATEWAY
###############################################################################

resource "aws_lambda_permission" "invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.xhtml_to_md.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

###############################################################################
# OUTPUT
###############################################################################

output "api_url" {
  description = "Invoke URL"
  value       = aws_apigatewayv2_api.api.api_endpoint
}