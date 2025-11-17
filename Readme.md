# XHTML to markdown converter

## Installing node modules for xhtml to markdown converter

npm i turndown jsdom

## Installing test and testServer node modules

npm i express body-parser

## Building package (in lambda directory)

zip -r function.zip index.js node_modules package.json

## AWS resources

|Resource type|Resource|Name|Other|
|-----|-----|-----|-----|
|Manually created|Identity Provider|token.actions.githubusercontent.com|Github Idp|
|Permanent|IAM role|gh-xhtmlToMarkdown|Permissions to deploy|
|Permanent|S3 bucket|terraform-state-xhtmltomarkdown|Object statuses|
|Permanent|DynamoDB|terraform-state-locks|Object locks|
|From Git|Lambda|xhtmlToMarkdown|Converter function|
|From Git|API Gateway|xhtml-to-md-api|Trigger for Lambda function|
|From Git|IAM role|xhtml-to-md-role|Role for deployment|