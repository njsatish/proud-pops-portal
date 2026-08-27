#!/bin/bash
set -euo pipefail

AWS_REGION="us-east-1"
DOMAIN="proudpops.denduluru.com"
ROOT_DOMAIN="denduluru.com"
BUCKET_NAME="${BUCKET_NAME:-proudpops-denduluru-demo}"
COMMENT="Proud Pops demo site"
CALLER_REF="proud-pops-v3-$(date -u +%Y%m%dT%H%M%SZ)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="$REPO_ROOT/public-site"
STATE_FILE="$REPO_ROOT/deployment/proud-pops-aws-state.env"

log(){ printf '\n[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail(){ echo "ERROR: $*" >&2; exit 1; }
command -v aws >/dev/null || fail "AWS CLI is not installed."
command -v python3 >/dev/null || fail "python3 is required."
[[ -f "$SITE_DIR/index.html" ]] || fail "$SITE_DIR/index.html is missing. Run V2 first."

log "Checking AWS identity"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ARN="$(aws sts get-caller-identity --query Arn --output text)"
echo "Account: $ACCOUNT_ID"
echo "Identity: $ARN"

log "Locating Route 53 hosted zone"
ZONE_ID="$(aws route53 list-hosted-zones-by-name --dns-name "$ROOT_DOMAIN" --query "HostedZones[?Name=='${ROOT_DOMAIN}.']|[0].Id" --output text | sed 's|/hostedzone/||')"
[[ -n "$ZONE_ID" && "$ZONE_ID" != "None" ]] || fail "Hosted zone for $ROOT_DOMAIN was not found."
echo "Hosted zone: $ZONE_ID"

log "Creating or confirming private S3 bucket"
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" >/dev/null
fi
aws s3api put-public-access-block --bucket "$BUCKET_NAME" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3 sync "$SITE_DIR/" "s3://$BUCKET_NAME/" --delete --exclude ".DS_Store" --cache-control "public,max-age=300"
aws s3 cp "$SITE_DIR/index.html" "s3://$BUCKET_NAME/index.html" --content-type "text/html; charset=utf-8" --cache-control "no-cache,no-store,must-revalidate"

log "Finding an ACM certificate that covers $DOMAIN"
CERT_ARN=""
for ARN_ITEM in $(aws acm list-certificates --region us-east-1 --certificate-statuses ISSUED --query 'CertificateSummaryList[].CertificateArn' --output text); do
  NAMES="$(aws acm describe-certificate --region us-east-1 --certificate-arn "$ARN_ITEM" --query 'Certificate.SubjectAlternativeNames' --output text)"
  if echo " $NAMES " | grep -Eq " (${DOMAIN//./\\.}|\\*\\.denduluru\\.com) "; then CERT_ARN="$ARN_ITEM"; break; fi
done

if [[ -z "$CERT_ARN" ]]; then
  log "Requesting a new ACM certificate"
  CERT_ARN="$(aws acm request-certificate --region us-east-1 --domain-name "$DOMAIN" --validation-method DNS --idempotency-token proudpops2026 --query CertificateArn --output text)"
  echo "Certificate requested: $CERT_ARN"
  log "Waiting for ACM DNS validation record"
  VALIDATION_NAME=""
  for _ in $(seq 1 30); do
    VALIDATION_NAME="$(aws acm describe-certificate --region us-east-1 --certificate-arn "$CERT_ARN" --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Name' --output text 2>/dev/null || true)"
    [[ -n "$VALIDATION_NAME" && "$VALIDATION_NAME" != "None" ]] && break
    sleep 3
  done
  [[ -n "$VALIDATION_NAME" && "$VALIDATION_NAME" != "None" ]] || fail "ACM validation record was not generated."
  VALIDATION_VALUE="$(aws acm describe-certificate --region us-east-1 --certificate-arn "$CERT_ARN" --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Value' --output text)"
  cat > /tmp/proud-pops-acm-dns.json <<JSON
{"Comment":"Validate Proud Pops ACM certificate","Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"$VALIDATION_NAME","Type":"CNAME","TTL":300,"ResourceRecords":[{"Value":"$VALIDATION_VALUE"}]}}]}
JSON
  aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch file:///tmp/proud-pops-acm-dns.json >/dev/null
  log "Waiting for ACM certificate issuance (can take several minutes)"
  aws acm wait certificate-validated --region us-east-1 --certificate-arn "$CERT_ARN"
else
  echo "Using certificate: $CERT_ARN"
fi

log "Creating or locating CloudFront Origin Access Control"
OAC_ID="$(aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='ProudPopsS3OAC']|[0].Id" --output text)"
if [[ -z "$OAC_ID" || "$OAC_ID" == "None" ]]; then
  cat > /tmp/proud-pops-oac.json <<'JSON'
{"Name":"ProudPopsS3OAC","Description":"OAC for Proud Pops private S3 origin","SigningProtocol":"sigv4","SigningBehavior":"always","OriginAccessControlOriginType":"s3"}
JSON
  OAC_ID="$(aws cloudfront create-origin-access-control --origin-access-control-config file:///tmp/proud-pops-oac.json --query 'OriginAccessControl.Id' --output text)"
fi
echo "OAC: $OAC_ID"

log "Creating or locating CloudFront distribution"
DIST_ID="$(aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '$DOMAIN')]|[0].Id" --output text)"
if [[ -z "$DIST_ID" || "$DIST_ID" == "None" ]]; then
  cat > /tmp/proud-pops-cf.json <<JSON
{
  "CallerReference":"$CALLER_REF",
  "Comment":"$COMMENT",
  "Enabled":true,
  "Aliases":{"Quantity":1,"Items":["$DOMAIN"]},
  "DefaultRootObject":"index.html",
  "Origins":{"Quantity":1,"Items":[{"Id":"ProudPopsS3Origin","DomainName":"$BUCKET_NAME.s3.us-east-1.amazonaws.com","OriginPath":"","CustomHeaders":{"Quantity":0},"S3OriginConfig":{"OriginAccessIdentity":""},"ConnectionAttempts":3,"ConnectionTimeout":10,"OriginAccessControlId":"$OAC_ID"}]},
  "DefaultCacheBehavior":{"TargetOriginId":"ProudPopsS3Origin","ViewerProtocolPolicy":"redirect-to-https","AllowedMethods":{"Quantity":3,"Items":["HEAD","GET","OPTIONS"],"CachedMethods":{"Quantity":3,"Items":["HEAD","GET","OPTIONS"]}},"Compress":true,"SmoothStreaming":false,"TrustedSigners":{"Enabled":false,"Quantity":0},"TrustedKeyGroups":{"Enabled":false,"Quantity":0},"FieldLevelEncryptionId":"","CachePolicyId":"658327ea-f89d-4fab-a63d-7e88639e58f6"},
  "CacheBehaviors":{"Quantity":0},"CustomErrorResponses":{"Quantity":0},
  "PriceClass":"PriceClass_100",
  "ViewerCertificate":{"CloudFrontDefaultCertificate":false,"ACMCertificateArn":"$CERT_ARN","SSLSupportMethod":"sni-only","MinimumProtocolVersion":"TLSv1.2_2021"},
  "Restrictions":{"GeoRestriction":{"RestrictionType":"none","Quantity":0}},
  "HttpVersion":"http2and3","IsIPV6Enabled":true
}
JSON
  DIST_ID="$(aws cloudfront create-distribution --distribution-config file:///tmp/proud-pops-cf.json --query 'Distribution.Id' --output text)"
fi
DIST_DOMAIN="$(aws cloudfront get-distribution --id "$DIST_ID" --query 'Distribution.DomainName' --output text)"
echo "Distribution: $DIST_ID"
echo "CloudFront domain: $DIST_DOMAIN"

log "Applying least-privilege S3 bucket policy for CloudFront"
cat > /tmp/proud-pops-bucket-policy.json <<JSON
{"Version":"2012-10-17","Statement":[{"Sid":"AllowCloudFrontServicePrincipalReadOnly","Effect":"Allow","Principal":{"Service":"cloudfront.amazonaws.com"},"Action":"s3:GetObject","Resource":"arn:aws:s3:::$BUCKET_NAME/*","Condition":{"StringEquals":{"AWS:SourceArn":"arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DIST_ID"}}}]}
JSON
aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy file:///tmp/proud-pops-bucket-policy.json

log "Creating Route 53 A and AAAA alias records"
CF_ZONE_ID="Z2FDTNDATAQYW2"
cat > /tmp/proud-pops-route53.json <<JSON
{"Comment":"Point Proud Pops subdomain to CloudFront","Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"$DOMAIN","Type":"A","AliasTarget":{"HostedZoneId":"$CF_ZONE_ID","DNSName":"$DIST_DOMAIN","EvaluateTargetHealth":false}}},{"Action":"UPSERT","ResourceRecordSet":{"Name":"$DOMAIN","Type":"AAAA","AliasTarget":{"HostedZoneId":"$CF_ZONE_ID","DNSName":"$DIST_DOMAIN","EvaluateTargetHealth":false}}}]}
JSON
aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch file:///tmp/proud-pops-route53.json >/dev/null

log "Creating initial CloudFront invalidation"
INVALIDATION_ID="$(aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths '/*' --query 'Invalidation.Id' --output text)"

cat > "$STATE_FILE" <<EOF
BUCKET_NAME=$BUCKET_NAME
DISTRIBUTION_ID=$DIST_ID
DISTRIBUTION_DOMAIN=$DIST_DOMAIN
DOMAIN=$DOMAIN
CERTIFICATE_ARN=$CERT_ARN
OAC_ID=$OAC_ID
HOSTED_ZONE_ID=$ZONE_ID
EOF

printf '\n=========================================\n'
printf 'PROUD POPS V3 INFRASTRUCTURE COMPLETE\n'
printf '=========================================\n'
printf 'Website: https://%s\n' "$DOMAIN"
printf 'CloudFront: %s (%s)\n' "$DIST_ID" "$DIST_DOMAIN"
printf 'Invalidation: %s\n' "$INVALIDATION_ID"
printf 'State file: %s\n' "$STATE_FILE"
printf '\nCloudFront may take several minutes to reach Deployed status.\n'
