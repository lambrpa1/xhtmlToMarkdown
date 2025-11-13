terraform {
  backend "s3" {
    bucket         = "terraform-state-xhtmltomarkdown"
    key            = "xhtml-to-md/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}