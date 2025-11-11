terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

# IAM role
resource "aws_iam_role" "lambda_role" {
  name = "xhtml-to-md-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda
resource "aws_lambda_function" "xhtml_to_md" {
  function_name    = "xhtmlToMarkdown"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  timeout          = 15
  memory_size      = 256
  filename         = "${path.module}/xhtmlToMd.zip"
  source_code_hash = filebase64sha256("${path.module}/xhtmlToMd.zip")
}

# API Gateway
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

resource "aws_lambda_permission" "invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.xhtml_to_md.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

output "api_url" {
  description = "Invoke URL"
  value       = aws_apigatewayv2_api.api.api_endpoint
}