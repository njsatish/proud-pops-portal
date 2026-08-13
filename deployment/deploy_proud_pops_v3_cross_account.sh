#!/bin/bash
set -euo pipefail

INFRA_PROFILE="${INFRA_PROFILE:-default}"
DNS_PROFILE="${DNS_PROFILE:-denduluru}"
AWS_REGION="us-east-1"
DOMAIN="proudpops.denduluru.com"
ROOT_DOMAIN="denduluru.com"
HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-Z21S238SFANDPM}"
BUCKET_NAME="${BUCKET_NAME:-proudpops-denduluru-demo}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="$REPO_ROOT/public-site"
STATE_FILE="$REPO_ROOT/deployment/proud-pops-aws-state.env"

log(){ printf '\n[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail(){ echo "ERROR: $*" >&2; exit 1; }

command -v aws >/dev/null || fail "AWS CLI is not installed."
[[ -f "$SITE_DIR/index.html" ]] || fail "$SITE_DIR/index.html does not exist. Run V2 first."

log "Checking infrastructure and DNS profiles"
INFRA_ACCOUNT="$(aws sts get-caller-identity --profile "$INFRA_PROFILE" --query Account --output text)"
DNS_ACCOUNT="$(aws sts get-caller-identity --profile "$DNS_PROFILE" --query Account --output text)"
echo "Infrastructure account: $INFRA_ACCOUNT ($INFRA_PROFILE)"
echo "DNS account: $DNS_ACCOUNT ($DNS_PROFILE)"
[[ "$INFRA_ACCOUNT" == "460425809139" ]] || fail "Unexpected infrastructure account: $INFRA_ACCOUNT"
[[ "$DNS_ACCOUNT" == "989174615155" ]] || fail "Unexpected DNS account: $DNS_ACCOUNT"

log "Confirming authoritative Route 53 hosted zone"
ZONE_NAME="$(aws route53 get-hosted-zone --profile "$DNS_PROFILE" --id "$HOSTED_ZONE_ID" --query 'HostedZone.Name' --output text)"
[[ "$ZONE_NAME" == "${ROOT_DOMAIN}." ]] || fail "Hosted zone $HOSTED_ZONE_ID is $ZONE_NAME, not ${ROOT_DOMAIN}."

log "Creating or confirming private S3 bucket"
if ! aws s3api head-bucket --profile "$INFRA_PROFILE" --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  aws s3api create-bucket --profile "$INFRA_PROFILE" --bucket "$BUCKET_NAME" --region "$AWS_REGION" >/dev/null
fi
aws s3api put-public-access-block --profile "$INFRA_PROFILE" --bucket "$BUCKET_NAME" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

log "Uploading website"
aws s3 sync "$SITE_DIR/" "s3://$BUCKET_NAME/" --profile "$INFRA_PROFILE" --delete --exclude ".DS_Store" --cache-control "public,max-age=300"
aws s3 cp "$SITE_DIR/index.html" "s3://$BUCKET_NAME/index.html" --profile "$INFRA_PROFILE" --content-type "text/html; charset=utf-8" --cache-control "no-cache,no-store,must-revalidate"

log "Finding or requesting ACM certificate for $DOMAIN"
CERT_ARN=""
for ITEM in $(aws acm list-certificates --profile "$INFRA_PROFILE" --region "$AWS_REGION" --certificate-statuses ISSUED PENDING_VALIDATION --query 'CertificateSummaryList[].CertificateArn' --output text); do
  NAMES="$(aws acm describe-certificate --profile "$INFRA_PROFILE" --region "$AWS_REGION" --certificate-arn "$ITEM" --query 'Certificate.SubjectAlternativeNames' --output text)"
  if echo " $NAMES " | grep -Fq " $DOMAIN "; then CERT_ARN="$ITEM"; break; fi
done

if [[ -z "$CERT_ARN" ]]; then
  CERT_ARN="$(aws acm request-certificate --profile "$INFRA_PROFILE" --region "$AWS_REGION" --domain-name "$DOMAIN" --validation-method DNS --idempotency-token proudpops2026 --query CertificateArn --output text)"
  echo "Requested certificate: $CERT_ARN"
fi

CERT_STATUS="$(aws acm describe-certificate --profile "$INFRA_PROFILE" --region "$AWS_REGION" --certificate-arn "$CERT_ARN" --query 'Certificate.Status' --output text)"
if [[ "$CERT_STATUS" != "ISSUED" ]]; then
  log "Retrieving ACM DNS validation record"
  VALIDATION_NAME=""
  for _ in $(seq 1 30); do
    VALIDATION_NAME="$(aws acm describe-certificate --profile "$INFRA_PROFILE" --region "$AWS_REGION" --certificate-arn "$CERT_ARN" --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Name' --output text 2>/dev/null || true)"
    [[ -n "$VALIDATION_NAME" && "$VALIDATION_NAME" != "None" ]] && break
    sleep 3
  done
  [[ -n "$VALIDATION_NAME" && "$VALIDATION_NAME" != "None" ]] || fail "ACM did not generate a validation record."
  VALIDATION_VALUE="$(aws acm describe-certificate --profile "$INFRA_PROFILE" --region "$AWS_REGION" --certificate-arn "$CERT_ARN" --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Value' --output text)"

  cat > /tmp/proud-pops-acm-validation.json <<JSON
{"Comment":"Validate Proud Pops ACM certificate","Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"$VALIDATION_NAME","Type":"CNAME","TTL":300,"ResourceRecords":[{"Value":"$VALIDATION_VALUE"}]}}]}
JSON
  aws route53 change-resource-record-sets --profile "$DNS_PROFILE" --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch file:///tmp/proud-pops-acm-validation.json >/dev/null
  log "Waiting for certificate validation"
  aws acm wait certificate-validated --profile "$INFRA_PROFILE" --region "$AWS_REGION" --certificate-arn "$CERT_ARN"
fi
echo "Certificate: $CERT_ARN"

log "Creating or locating CloudFront Origin Access Control"
OAC_ID="$(aws cloudfront list-origin-access-controls --profile "$INFRA_PROFILE" --query "OriginAccessControlList.Items[?Name=='ProudPopsS3OAC']|[0].Id" --output text)"
if [[ -z "$OAC_ID" || "$OAC_ID" == "None" ]]; then
  cat > /tmp/proud-pops-oac.json <<'JSON'
{"Name":"ProudPopsS3OAC","Description":"OAC for Proud Pops private S3 origin","SigningProtocol":"sigv4","SigningBehavior":"always","OriginAccessControlOriginType":"s3"}
JSON
  OAC_ID="$(aws cloudfront create-origin-access-control --profile "$INFRA_PROFILE" --origin-access-control-config file:///tmp/proud-pops-oac.json --query 'OriginAccessControl.Id' --output text)"
fi

log "Creating or locating Proud Pops CloudFront distribution"
DIST_ID="$(aws cloudfront list-distributions --profile "$INFRA_PROFILE" --query "DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '$DOMAIN')]|[0].Id" --output text)"
if [[ -z "$DIST_ID" || "$DIST_ID" == "None" ]]; then
  CALLER_REF="proud-pops-$(date -u +%Y%m%dT%H%M%SZ)"
  cat > /tmp/proud-pops-cloudfront.json <<JSON
{
  "CallerReference":"$CALLER_REF",
  "Comment":"Proud Pops demo site",
  "Enabled":true,
  "Aliases":{"Quantity":1,"Items":["$DOMAIN"]},
  "DefaultRootObject":"index.html",
  "Origins":{"Quantity":1,"Items":[{"Id":"ProudPopsS3Origin","DomainName":"$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com","OriginPath":"","CustomHeaders":{"Quantity":0},"S3OriginConfig":{"OriginAccessIdentity":""},"ConnectionAttempts":3,"ConnectionTimeout":10,"OriginAccessControlId":"$OAC_ID"}]},
  "DefaultCacheBehavior":{"TargetOriginId":"ProudPopsS3Origin","ViewerProtocolPolicy":"redirect-to-https","AllowedMethods":{"Quantity":3,"Items":["HEAD","GET","OPTIONS"],"CachedMethods":{"Quantity":3,"Items":["HEAD","GET","OPTIONS"]}},"Compress":true,"SmoothStreaming":false,"TrustedSigners":{"Enabled":false,"Quantity":0},"TrustedKeyGroups":{"Enabled":false,"Quantity":0},"FieldLevelEncryptionId":"","CachePolicyId":"658327ea-f89d-4fab-a63d-7e88639e58f6"},
  "CacheBehaviors":{"Quantity":0},
  "CustomErrorResponses":{"Quantity":0},
  "PriceClass":"PriceClass_100",
  "ViewerCertificate":{"CloudFrontDefaultCertificate":false,"ACMCertificateArn":"$CERT_ARN","SSLSupportMethod":"sni-only","MinimumProtocolVersion":"TLSv1.2_2021"},
  "Restrictions":{"GeoRestriction":{"RestrictionType":"none","Quantity":0}},
  "HttpVersion":"http2and3",
  "IsIPV6Enabled":true
}
JSON
  DIST_ID="$(aws cloudfront create-distribution --profile "$INFRA_PROFILE" --distribution-config file:///tmp/proud-pops-cloudfront.json --query 'Distribution.Id' --output text)"
fi
DIST_DOMAIN="$(aws cloudfront get-distribution --profile "$INFRA_PROFILE" --id "$DIST_ID" --query 'Distribution.DomainName' --output text)"
echo "Distribution: $DIST_ID"
echo "CloudFront domain: $DIST_DOMAIN"

log "Granting CloudFront read access to the private bucket"
cat > /tmp/proud-pops-bucket-policy.json <<JSON
{"Version":"2012-10-17","Statement":[{"Sid":"AllowCloudFrontServicePrincipalReadOnly","Effect":"Allow","Principal":{"Service":"cloudfront.amazonaws.com"},"Action":"s3:GetObject","Resource":"arn:aws:s3:::$BUCKET_NAME/*","Condition":{"StringEquals":{"AWS:SourceArn":"arn:aws:cloudfront::$INFRA_ACCOUNT:distribution/$DIST_ID"}}}]}
JSON
aws s3api put-bucket-policy --profile "$INFRA_PROFILE" --bucket "$BUCKET_NAME" --policy file:///tmp/proud-pops-bucket-policy.json

log "Creating Proud Pops DNS records in the Denduluru account"
CF_ZONE_ID="Z2FDTNDATAQYW2"
cat > /tmp/proud-pops-route53.json <<JSON
{"Comment":"Point Proud Pops to CloudFront","Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"$DOMAIN","Type":"A","AliasTarget":{"HostedZoneId":"$CF_ZONE_ID","DNSName":"$DIST_DOMAIN","EvaluateTargetHealth":false}}},{"Action":"UPSERT","ResourceRecordSet":{"Name":"$DOMAIN","Type":"AAAA","AliasTarget":{"HostedZoneId":"$CF_ZONE_ID","DNSName":"$DIST_DOMAIN","EvaluateTargetHealth":false}}}]}
JSON
aws route53 change-resource-record-sets --profile "$DNS_PROFILE" --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch file:///tmp/proud-pops-route53.json >/dev/null

log "Creating CloudFront invalidation"
INVALIDATION_ID="$(aws cloudfront create-invalidation --profile "$INFRA_PROFILE" --distribution-id "$DIST_ID" --paths '/*' --query 'Invalidation.Id' --output text)"

cat > "$STATE_FILE" <<STATE
INFRA_PROFILE=$INFRA_PROFILE
DNS_PROFILE=$DNS_PROFILE
INFRA_ACCOUNT=$INFRA_ACCOUNT
DNS_ACCOUNT=$DNS_ACCOUNT
BUCKET_NAME=$BUCKET_NAME
DISTRIBUTION_ID=$DIST_ID
DISTRIBUTION_DOMAIN=$DIST_DOMAIN
DOMAIN=$DOMAIN
CERTIFICATE_ARN=$CERT_ARN
OAC_ID=$OAC_ID
HOSTED_ZONE_ID=$HOSTED_ZONE_ID
STATE

printf '\n=========================================\n'
printf 'PROUD POPS CROSS-ACCOUNT DEPLOYMENT COMPLETE\n'
printf '=========================================\n'
printf 'Website: https://%s\n' "$DOMAIN"
printf 'CloudFront: %s\n' "$DIST_ID"
printf 'Invalidation: %s\n' "$INVALIDATION_ID"
printf 'State: %s\n' "$STATE_FILE"
printf '\nCloudFront can take several minutes to become Deployed.\n'
