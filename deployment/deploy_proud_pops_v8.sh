#!/bin/bash
set -euo pipefail
PROFILE="${INFRA_PROFILE:-default}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/deployment/proud-pops-aws-state.env"
[[ -f "$STATE" ]] || { echo "ERROR: Complete V3 first; missing $STATE"; exit 1; }
source "$STATE"
REGION=us-east-1
TABLE=proud-pops-announcements
POOL=proud-pops-admin-users
ROLE=proud-pops-announcements-lambda-role
FUNCTION=proud-pops-announcements-api
API_NAME=proud-pops-admin-api
read -r -p "Initial admin username [proudpopsadmin]: " ADMIN_USER
ADMIN_USER="${ADMIN_USER:-proudpopsadmin}"
while true; do read -r -s -p "Initial password (8+ chars, upper/lower/number/symbol): " ADMIN_PASSWORD; echo; [[ ${#ADMIN_PASSWORD} -ge 8 ]] && [[ "$ADMIN_PASSWORD" =~ [A-Z] ]] && [[ "$ADMIN_PASSWORD" =~ [a-z] ]] && [[ "$ADMIN_PASSWORD" =~ [0-9] ]] && [[ "$ADMIN_PASSWORD" =~ [^a-zA-Z0-9] ]] && break; echo "Password does not meet policy."; done
aws dynamodb describe-table --profile "$PROFILE" --region "$REGION" --table-name "$TABLE" >/dev/null 2>&1 || aws dynamodb create-table --profile "$PROFILE" --region "$REGION" --table-name "$TABLE" --attribute-definitions AttributeName=id,AttributeType=S --key-schema AttributeName=id,KeyType=HASH --billing-mode PAY_PER_REQUEST >/dev/null
aws dynamodb wait table-exists --profile "$PROFILE" --region "$REGION" --table-name "$TABLE"
POOL_ID="$(aws cognito-idp list-user-pools --profile "$PROFILE" --region "$REGION" --max-results 60 --query "UserPools[?Name=='$POOL']|[0].Id" --output text)"
if [[ -z "$POOL_ID" || "$POOL_ID" == None ]]; then POOL_ID="$(aws cognito-idp create-user-pool --profile "$PROFILE" --region "$REGION" --pool-name "$POOL" --username-configuration CaseSensitive=false --policies 'PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=true,TemporaryPasswordValidityDays=7}' --admin-create-user-config AllowAdminCreateUserOnly=true --query UserPool.Id --output text)"; fi
CLIENT_ID="$(aws cognito-idp list-user-pool-clients --profile "$PROFILE" --region "$REGION" --user-pool-id "$POOL_ID" --query "UserPoolClients[?ClientName=='proud-pops-admin-web']|[0].ClientId" --output text)"
if [[ -z "$CLIENT_ID" || "$CLIENT_ID" == None ]]; then CLIENT_ID="$(aws cognito-idp create-user-pool-client --profile "$PROFILE" --region "$REGION" --user-pool-id "$POOL_ID" --client-name proud-pops-admin-web --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH --prevent-user-existence-errors ENABLED --query UserPoolClient.ClientId --output text)"; fi
aws cognito-idp admin-get-user --profile "$PROFILE" --region "$REGION" --user-pool-id "$POOL_ID" --username "$ADMIN_USER" >/dev/null 2>&1 || aws cognito-idp admin-create-user --profile "$PROFILE" --region "$REGION" --user-pool-id "$POOL_ID" --username "$ADMIN_USER" --message-action SUPPRESS >/dev/null
aws cognito-idp admin-set-user-password --profile "$PROFILE" --region "$REGION" --user-pool-id "$POOL_ID" --username "$ADMIN_USER" --password "$ADMIN_PASSWORD" --permanent
unset ADMIN_PASSWORD
cat >/tmp/pp-trust.json <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
ROLE_ARN="$(aws iam get-role --profile "$PROFILE" --role-name "$ROLE" --query Role.Arn --output text 2>/dev/null || true)"
if [[ -z "$ROLE_ARN" ]]; then ROLE_ARN="$(aws iam create-role --profile "$PROFILE" --role-name "$ROLE" --assume-role-policy-document file:///tmp/pp-trust.json --query Role.Arn --output text)"; aws iam attach-role-policy --profile "$PROFILE" --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole; fi
cat >/tmp/pp-policy.json <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dynamodb:Scan","dynamodb:PutItem","dynamodb:DeleteItem"],"Resource":"arn:aws:dynamodb:$REGION:$INFRA_ACCOUNT:table/$TABLE"},{"Effect":"Allow","Action":"cognito-idp:InitiateAuth","Resource":"*"}]}
JSON
aws iam put-role-policy --profile "$PROFILE" --role-name "$ROLE" --policy-name ProudPopsAnnouncementsAccess --policy-document file:///tmp/pp-policy.json
sleep 10
(cd "$ROOT/lambdas/announcements" && zip -q -j /tmp/pp-lambda.zip lambda_function.py)
if aws lambda get-function --profile "$PROFILE" --region "$REGION" --function-name "$FUNCTION" >/dev/null 2>&1; then aws lambda update-function-code --profile "$PROFILE" --region "$REGION" --function-name "$FUNCTION" --zip-file fileb:///tmp/pp-lambda.zip >/dev/null; aws lambda wait function-updated --profile "$PROFILE" --region "$REGION" --function-name "$FUNCTION"; aws lambda update-function-configuration --profile "$PROFILE" --region "$REGION" --function-name "$FUNCTION" --environment "Variables={TABLE_NAME=$TABLE,CLIENT_ID=$CLIENT_ID}" >/dev/null; else aws lambda create-function --profile "$PROFILE" --region "$REGION" --function-name "$FUNCTION" --runtime python3.12 --handler lambda_function.handler --role "$ROLE_ARN" --zip-file fileb:///tmp/pp-lambda.zip --timeout 15 --environment "Variables={TABLE_NAME=$TABLE,CLIENT_ID=$CLIENT_ID}" >/dev/null; fi
FN_ARN="$(aws lambda get-function --profile "$PROFILE" --region "$REGION" --function-name "$FUNCTION" --query Configuration.FunctionArn --output text)"
API_ID="$(aws apigatewayv2 get-apis --profile "$PROFILE" --region "$REGION" --query "Items[?Name=='$API_NAME']|[0].ApiId" --output text)"
if [[ -z "$API_ID" || "$API_ID" == None ]]; then API_ID="$(aws apigatewayv2 create-api --profile "$PROFILE" --region "$REGION" --name "$API_NAME" --protocol-type HTTP --cors-configuration '{"AllowOrigins":["https://proudpops.denduluru.com"],"AllowMethods":["GET","POST","PUT","DELETE","OPTIONS"],"AllowHeaders":["authorization","content-type"],"MaxAge":300}' --query ApiId --output text)"; fi
INT_ID="$(aws apigatewayv2 get-integrations --profile "$PROFILE" --region "$REGION" --api-id "$API_ID" --query 'Items[0].IntegrationId' --output text)"; if [[ -z "$INT_ID" || "$INT_ID" == None ]]; then INT_ID="$(aws apigatewayv2 create-integration --profile "$PROFILE" --region "$REGION" --api-id "$API_ID" --integration-type AWS_PROXY --integration-uri "$FN_ARN" --payload-format-version 2.0 --query IntegrationId --output text)"; fi
AUTH_ID="$(aws apigatewayv2 get-authorizers --profile "$PROFILE" --region "$REGION" --api-id "$API_ID" --query 'Items[0].AuthorizerId' --output text)"; if [[ -z "$AUTH_ID" || "$AUTH_ID" == None ]]; then AUTH_ID="$(aws apigatewayv2 create-authorizer --profile "$PROFILE" --region "$REGION" --api-id "$API_ID" --authorizer-type JWT --name ProudPopsCognito --identity-source '$request.header.Authorization' --jwt-configuration "Audience=$CLIENT_ID,Issuer=https://cognito-idp.$REGION.amazonaws.com/$POOL_ID" --query AuthorizerId --output text)"; fi
for R in 'POST /login' 'GET /announcements'; do aws apigatewayv2 get-routes --profile "$PROFILE" --region "$REGION" --api-id "$API_ID" --query "Items[?RouteKey=='$R'].RouteId|[0]" --output text | grep -vqE 'None|^$' || aws apigatewayv2 create-route --profile "$PROFILE" --region "$REGION" --api-id "$API_ID" --route-key "$R" --target "integrations/$INT_ID" >/dev/null; done
for R in 'GET /admin/announcements' 'POST /admin/announcements' 'PUT /admin/announcements/{id}' 'DELETE /admin/announcements/{id}'; do aws apigatewayv2 get-routes --profile "$PROFILE" --region "$REGION" --api-id "$API_ID" --query "Items[?RouteKey=='$R'].RouteId|[0]" --output text | grep -vqE 'None|^$' || aws apigatewayv2 create-route --profile "$PROFILE" --region "$REGION" --api-id "$API_ID" --route-key "$R" --target "integrations/$INT_ID" --authorization-type JWT --authorizer-id "$AUTH_ID" >/dev/null; done
aws apigatewayv2 get-stages --profile "$PROFILE" --region "$REGION" --api-id "$API_ID" --query "Items[?StageName=='\$default'].StageName|[0]" --output text | grep -vqE 'None|^$' || aws apigatewayv2 create-stage --profile "$PROFILE" --region "$REGION" --api-id "$API_ID" --stage-name '$default' --auto-deploy >/dev/null
aws lambda add-permission --profile "$PROFILE" --region "$REGION" --function-name "$FUNCTION" --statement-id apigw-invoke --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:$REGION:$INFRA_ACCOUNT:$API_ID/*/*/*" >/dev/null 2>&1 || true
API_URL="https://$API_ID.execute-api.$REGION.amazonaws.com"
sed "s|__API_URL__|$API_URL|g" "$ROOT/public-site/admin/config.js" > /tmp/config.js && mv /tmp/config.js "$ROOT/public-site/admin/config.js"
grep -q 'announcements.js' "$ROOT/public-site/index.html" || sed -i.bak "s|</body>|<script>window.PROUD_POPS_API='$API_URL';</script><script src='announcements.js'></script></body>|" "$ROOT/public-site/index.html"
rm -f "$ROOT/public-site/index.html.bak"
aws s3 sync "$ROOT/public-site/" "s3://$BUCKET_NAME/" --profile "$PROFILE" --delete --exclude '.DS_Store' --cache-control 'public,max-age=300'
aws s3 cp "$ROOT/public-site/index.html" "s3://$BUCKET_NAME/index.html" --profile "$PROFILE" --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate'
aws cloudfront create-invalidation --profile "$PROFILE" --distribution-id "$DISTRIBUTION_ID" --paths '/*' >/dev/null
cat > "$ROOT/deployment/proud-pops-v8-state.env" <<STATE
API_URL=$API_URL
API_ID=$API_ID
USER_POOL_ID=$POOL_ID
APP_CLIENT_ID=$CLIENT_ID
TABLE_NAME=$TABLE
ADMIN_USERNAME=$ADMIN_USER
STATE
printf '\nV8 deployed.\nAdmin: https://%s/admin/\nPublic site: https://%s\nUsername: %s\n' "$DOMAIN" "$DOMAIN" "$ADMIN_USER"
