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

# Kuka tätä ajaa (vain tulosteita varten)
data "aws_caller_identity" "current" {}

###############################################################################
# S3 BUCKET FOR TERRAFORM-STATE
###############################################################################

resource "aws_s3_bucket" "tf_state" {
  bucket = "terraform-state-xhtmltomarkdown"

  tags = {
    Name        = "Terraform remote state bucket"
    Environment = "shared"
  }
}

# Estetään public access varmuuden vuoksi
resource "aws_s3_bucket_public_access_block" "tf_state_block" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# (valinnainen mutta järkevä) versiointi state-tiedostolle
resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

###############################################################################
# DYNAMODB TABLE FOR TERRAFORM LOCK
###############################################################################

resource "aws_dynamodb_table" "tf_locks" {
  name         = "terraform-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform state lock table"
    Environment = "shared"
  }
}

###############################################################################
# GITHUB OIDC PROVIDER (DATA) – THIS MUST ALREADY EXIST IN AWS
###############################################################################

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

###############################################################################
# IAM ROLE FOR GH: gh-xhtmlToMarkdown
###############################################################################

# Trust policy GitHub Actionsille (repo: lambrpa1/xhtmlToMarkdown)
data "aws_iam_policy_document" "gh_assume" {
  statement {
    sid    = "GitHubActionsOIDC"
    effect = "Allow"
    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:lambrpa1/xhtmlToMarkdown:*"]
    }
  }
}

resource "aws_iam_role" "gh_xhtml" {
  name               = "gh-xhtmlToMarkdown"
  assume_role_policy = data.aws_iam_policy_document.gh_assume.json

  description = "GitHub Actions role for xhtmlToMarkdown Terraform deploys"
}

###############################################################################
# RIGHTS: S3 + DYNAMODB BACKEND + LAMBDA/APIGW/LOGS/IAM
###############################################################################

data "aws_iam_policy_document" "gh_permissions" {
  # S3 backend
  statement {
    sid    = "S3StateAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*"
    ]
  }

  # DynamoDB lock table
  statement {
    sid    = "DynamoDBStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem"
    ]
    resources = [
      aws_dynamodb_table.tf_locks.arn
    ]
  }

  # Lambda & API Gateway & Logs 
  statement {
    sid    = "LambdaAndApiGateway"
    effect = "Allow"
    actions = [
      # Lambda – all privileges
      "lambda:*",
  
      # API Gateway v2 (HTTP/WebSocket APIs)
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:PATCH",
      "apigateway:DELETE",

      # Logs
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }

  # IAM for Lambda
  statement {
    sid    = "ManageLambdaExecRole"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:GetRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:GetRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListInstanceProfilesForRole",
      "iam:DeleteRole"            
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/xhtml-to-md-role"
    ]
  }

  # IAM PassRole execution roolille (xhtml-to-md-role)
  statement {
    sid    = "PassLambdaExecRole"
    effect = "Allow"
    actions = [
      "iam:PassRole",
      "iam:GetRole",
      "iam:CreateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/xhtml-to-md-role"
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "gh_policy" {
  name   = "gh-xhtmlToMarkdown-policy"
  policy = data.aws_iam_policy_document.gh_permissions.json
}

resource "aws_iam_role_policy_attachment" "gh_attach" {
  role       = aws_iam_role.gh_xhtml.name
  policy_arn = aws_iam_policy.gh_policy.arn
}

###############################################################################
# OUTPUTS
###############################################################################

output "state_bucket" {
  value       = aws_s3_bucket.tf_state.bucket
  description = "Terraform state S3 bucket"
}

output "lock_table" {
  value       = aws_dynamodb_table.tf_locks.name
  description = "Terraform lock DynamoDB table"
}

output "gh_role_arn" {
  value       = aws_iam_role.gh_xhtml.arn
  description = "GitHub Actions IAM role ARN (role-to-assume)"
}