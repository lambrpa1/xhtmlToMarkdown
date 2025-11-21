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
# API GATEWAY REST API
###############################################################################

data "aws_region" "current" {}

resource "aws_api_gateway_rest_api" "api" {
  name        = "xhtml-to-md-api"
  description = "REST API for XHTML to Markdown converter Lambda"
}

# POST /convert -metodi
resource "aws_api_gateway_method" "post_root" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_rest_api.api.root_resource_id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda-integraatio REST API:lle
resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.post_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.xhtml_to_md.arn}/invocations"
}

# Deployment (riippuu metodista ja integraatiosta)
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_method.post_root,
    aws_api_gateway_integration.lambda,
  ]

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_method.post_root.id,
      aws_api_gateway_integration.lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id
  stage_name    = "convert"
}

###############################################################################
# LAMBDA PERMISSION FOR API GATEWAY
###############################################################################

resource "aws_lambda_permission" "invoke" {
  statement_id  = "AllowAPIGatewayInvokeRest"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.xhtml_to_md.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

###############################################################################
# OUTPUT
###############################################################################

output "api_url" {
  description = "Invoke URL"
  value       = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.stage.stage_name}"
}