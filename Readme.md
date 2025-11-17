# XHTML to markdown converter

## Local run

### Installing node modules for xhtml to markdown converter

```
cd lambda
npm i turndown jsdom
```

### Installing test and testServer node modules

```
cd test
npm i express body-parser
```

### Testing 

```
cd test
node test.js 
```

### Running local server

Local server starts at http://localhost:3000/ and endpoint available http://localhost:3000/convert

```
cd test
node testServer.js

curl -s http://localhost:3000/convert \                       
  -H "Content-Type: application/json" \
  -d '{"xhtml":"<h1>Hei</h1><p>Testi</p>"}' | jq .
```


## AWS resources

“Manually created resources” refers to resources that are configured directly in the AWS Console.

“Permanent resources” are bootstrap resources that are created once using Terraform definitions.

“From Git” means resources that are created or updated automatically by a GitHub Action on each deployment.

|Resource type|Resource|Name|Other|
|-----|-----|-----|-----|
|Manually created|Identity Provider|token.actions.githubusercontent.com|Github Idp|
|Permanent|IAM role|gh-xhtmlToMarkdown|Permissions to deploy|
|Permanent|S3 bucket|terraform-state-xhtmltomarkdown|Object statuses|
|Permanent|DynamoDB|terraform-state-locks|Object locks|
|From Git|Lambda|xhtmlToMarkdown|Converter function|
|From Git|API Gateway|xhtml-to-md-api|Trigger for Lambda function|
|From Git|IAM role|xhtml-to-md-role|Role for deployment|