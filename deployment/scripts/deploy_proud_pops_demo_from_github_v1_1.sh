#!/usr/bin/env bash
set -euo pipefail

# Proud Pops demo deployment from GitHub into the isolated demo AWS account.
EXPECTED_AWS_ACCOUNT="${PROUDPOPS_DEMO_AWS_ACCOUNT:-019051663952}"
AWS_PROFILE_NAME="${PROUDPOPS_DEMO_AWS_PROFILE:-proud-pops-demo}"
REGION="${AWS_REGION:-us-east-1}"
GITHUB_REPO="${PROUDPOPS_GITHUB_REPO:-https://github.com/njsatish/proud-pops-portal.git}"
GITHUB_BRANCH="${PROUDPOPS_GITHUB_BRANCH:-proud-pops-v1}"
EXPECTED_COMMIT="${PROUDPOPS_EXPECTED_COMMIT:-}"
BUCKET_NAME="${PROUDPOPS_DEMO_BUCKET:-proud-pops-demo-${EXPECTED_AWS_ACCOUNT}-${REGION}}"
OAC_NAME="${PROUDPOPS_DEMO_OAC:-proud-pops-demo-oac-${EXPECTED_AWS_ACCOUNT}}"
DISTRIBUTION_COMMENT="Proud Pops demo from GitHub account ${EXPECTED_AWS_ACCOUNT}"
STATE_DIR="${PROUDPOPS_DEMO_STATE_DIR:-$HOME/.config/proud-pops-demo}"
STATE_FILE="$STATE_DIR/aws-state.env"
WORK_DIR="$(mktemp -d)"
REPO_DIR="$WORK_DIR/proud-pops-portal"
PUBLIC_SITE="$REPO_DIR/public-site"
SUCCESS=0

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }
read_state(){ [[ -f "$STATE_FILE" ]] && sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1 || true; }

cleanup(){
  local code=$?
  trap - EXIT INT TERM
  rm -rf "$WORK_DIR"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

log "=== Proud Pops Demo AWS Deployment From GitHub V1.1 ==="
log "AWS profile: $AWS_PROFILE_NAME"
log "Expected account: $EXPECTED_AWS_ACCOUNT"
log "Region: $REGION"
log "GitHub: $GITHUB_REPO"
log "Branch: $GITHUB_BRANCH"
log "Bucket: $BUCKET_NAME"

for command in aws git curl python3; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is required."
done

ACTUAL_ACCOUNT="$(aws_cmd sts get-caller-identity --query Account --output text)"
ACTUAL_ARN="$(aws_cmd sts get-caller-identity --query Arn --output text)"
[[ "$ACTUAL_ACCOUNT" == "$EXPECTED_AWS_ACCOUNT" ]] || fail "Wrong AWS account: $ACTUAL_ACCOUNT"
[[ "$ACTUAL_ARN" == *":user/proud-pops-demo-deployer" ]] || fail "Unexpected IAM identity: $ACTUAL_ARN"
log "PASS AWS identity: $ACTUAL_ARN"

REMOTE_COMMIT="$(git ls-remote "$GITHUB_REPO" "refs/heads/$GITHUB_BRANCH" | awk '{print $1}')"
[[ -n "$REMOTE_COMMIT" ]] || fail "GitHub branch was not found: $GITHUB_BRANCH"
if [[ -n "$EXPECTED_COMMIT" && "$REMOTE_COMMIT" != "$EXPECTED_COMMIT" ]]; then
  fail "GitHub commit $REMOTE_COMMIT does not match expected commit $EXPECTED_COMMIT"
fi
log "GitHub commit: $REMOTE_COMMIT"

git clone --depth 1 --branch "$GITHUB_BRANCH" "$GITHUB_REPO" "$REPO_DIR"
CLONED_COMMIT="$(git -C "$REPO_DIR" rev-parse HEAD)"
[[ "$CLONED_COMMIT" == "$REMOTE_COMMIT" ]] || fail "Cloned commit differs from GitHub."
[[ -s "$PUBLIC_SITE/index.html" ]] || fail "public-site/index.html is missing in GitHub."
for required in book.html services.html about.html gallery.html contact.html assets/css/site.css; do
  [[ -s "$PUBLIC_SITE/$required" ]] || fail "GitHub public-site is missing: $required"
done

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

if ! aws_cmd s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  log "Creating private S3 bucket..."
  if [[ "$REGION" == "us-east-1" ]]; then
    aws_cmd s3api create-bucket --bucket "$BUCKET_NAME" >/dev/null
  else
    aws_cmd s3api create-bucket --bucket "$BUCKET_NAME" \
      --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
  fi
fi

aws_cmd s3api put-public-access-block --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
aws_cmd s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

OAC_ID="$(read_state OAC_ID)"
if [[ -z "$OAC_ID" ]]; then
  OAC_ID="$(aws_cmd cloudfront list-origin-access-controls \
    --query "OriginAccessControlList.Items[?Name=='$OAC_NAME'].Id | [0]" --output text)"
  [[ "$OAC_ID" == "None" ]] && OAC_ID=""
fi
if [[ -z "$OAC_ID" ]]; then
  cat > "$WORK_DIR/oac.json" <<JSON
{
  "Name": "$OAC_NAME",
  "Description": "Private S3 access for Proud Pops demo",
  "SigningProtocol": "sigv4",
  "SigningBehavior": "always",
  "OriginAccessControlOriginType": "s3"
}
JSON
  OAC_ID="$(aws_cmd cloudfront create-origin-access-control \
    --origin-access-control-config "file://$WORK_DIR/oac.json" \
    --query 'OriginAccessControl.Id' --output text)"
fi
[[ -n "$OAC_ID" && "$OAC_ID" != "None" ]] || fail "Could not create or find CloudFront OAC."
log "OAC: $OAC_ID"

DISTRIBUTION_ID="$(read_state DISTRIBUTION_ID)"
if [[ -n "$DISTRIBUTION_ID" ]]; then
  if ! aws_cmd cloudfront get-distribution --id "$DISTRIBUTION_ID" >/dev/null 2>&1; then
    DISTRIBUTION_ID=""
  fi
fi

if [[ -z "$DISTRIBUTION_ID" ]]; then
  CALLER_REFERENCE="proud-pops-demo-$EXPECTED_AWS_ACCOUNT-$(date +%s)"
  cat > "$WORK_DIR/distribution.json" <<JSON
{
  "CallerReference": "$CALLER_REFERENCE",
  "Comment": "$DISTRIBUTION_COMMENT",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "proud-pops-demo-s3",
      "DomainName": "$BUCKET_NAME.s3.$REGION.amazonaws.com",
      "OriginPath": "",
      "CustomHeaders": {"Quantity": 0},
      "S3OriginConfig": {"OriginAccessIdentity": ""},
      "ConnectionAttempts": 3,
      "ConnectionTimeout": 10,
      "OriginAccessControlId": "$OAC_ID",
      "OriginShield": {"Enabled": false}
    }]
  },
  "OriginGroups": {"Quantity": 0},
  "DefaultCacheBehavior": {
    "TargetOriginId": "proud-pops-demo-s3",
    "TrustedSigners": {"Enabled": false, "Quantity": 0},
    "TrustedKeyGroups": {"Enabled": false, "Quantity": 0},
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["HEAD", "GET"],
      "CachedMethods": {"Quantity": 2, "Items": ["HEAD", "GET"]}
    },
    "SmoothStreaming": false,
    "Compress": true,
    "LambdaFunctionAssociations": {"Quantity": 0},
    "FunctionAssociations": {"Quantity": 0},
    "FieldLevelEncryptionId": "",
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "GrpcConfig": {"Enabled": false}
  },
  "CacheBehaviors": {"Quantity": 0},
  "CustomErrorResponses": {"Quantity": 0},
  "Logging": {"Enabled": false, "IncludeCookies": false, "Bucket": "", "Prefix": ""},
  "PriceClass": "PriceClass_100",
  "ViewerCertificate": {
    "CloudFrontDefaultCertificate": true,
    "SSLSupportMethod": "vip",
    "MinimumProtocolVersion": "TLSv1",
    "CertificateSource": "cloudfront"
  },
  "Restrictions": {
    "GeoRestriction": {"RestrictionType": "none", "Quantity": 0}
  },
  "WebACLId": "",
  "HttpVersion": "http2and3",
  "IsIPV6Enabled": true,
  "Staging": false,
  "ContinuousDeploymentPolicyId": ""
}
JSON
  DISTRIBUTION_ID="$(aws_cmd cloudfront create-distribution \
    --distribution-config "file://$WORK_DIR/distribution.json" \
    --query 'Distribution.Id' --output text)"
fi
[[ -n "$DISTRIBUTION_ID" && "$DISTRIBUTION_ID" != "None" ]] || fail "Could not create CloudFront distribution."

DISTRIBUTION_ARN="arn:aws:cloudfront::$EXPECTED_AWS_ACCOUNT:distribution/$DISTRIBUTION_ID"
cat > "$WORK_DIR/bucket-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontServicePrincipalReadOnly",
    "Effect": "Allow",
    "Principal": {"Service": "cloudfront.amazonaws.com"},
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BUCKET_NAME/*",
    "Condition": {
      "StringEquals": {"AWS:SourceArn": "$DISTRIBUTION_ARN"}
    }
  }]
}
JSON
aws_cmd s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy "file://$WORK_DIR/bucket-policy.json"

log "Uploading GitHub public-site to private S3 bucket..."
aws_cmd s3 sync "$PUBLIC_SITE/" "s3://$BUCKET_NAME/" --delete \
  --exclude '*.html' \
  --cache-control 'public,max-age=3600,must-revalidate'
aws_cmd s3 sync "$PUBLIC_SITE/" "s3://$BUCKET_NAME/" \
  --exclude '*' --include '*.html' \
  --cache-control 'no-cache,no-store,must-revalidate' \
  --content-type 'text/html; charset=utf-8'

cat > "$STATE_FILE" <<STATE
AWS_ACCOUNT=$EXPECTED_AWS_ACCOUNT
AWS_PROFILE=$AWS_PROFILE_NAME
AWS_REGION=$REGION
GITHUB_REPO=$GITHUB_REPO
GITHUB_BRANCH=$GITHUB_BRANCH
GITHUB_COMMIT=$CLONED_COMMIT
BUCKET_NAME=$BUCKET_NAME
OAC_ID=$OAC_ID
DISTRIBUTION_ID=$DISTRIBUTION_ID
STATE
chmod 600 "$STATE_FILE"

log "Waiting for CloudFront deployment..."
aws_cmd cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"
DISTRIBUTION_DOMAIN="$(aws_cmd cloudfront get-distribution --id "$DISTRIBUTION_ID" \
  --query 'Distribution.DomainName' --output text)"
[[ -n "$DISTRIBUTION_DOMAIN" && "$DISTRIBUTION_DOMAIN" != "None" ]] || fail "CloudFront domain was not returned."
DEMO_URL="https://$DISTRIBUTION_DOMAIN"

INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths '/*' --query 'Invalidation.Id' --output text)"
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

log "Verifying demo site..."
for path in / /index.html /book.html /services.html /about.html /gallery.html /contact.html /assets/css/site.css; do
  output="$WORK_DIR/$(printf '%s' "$path" | tr '/.' '__')"
  code="$(curl -sS -L -o "$output" -w '%{http_code}' "$DEMO_URL$path?commit=$CLONED_COMMIT")"
  [[ "$code" == "200" ]] || fail "$DEMO_URL$path returned HTTP $code"
  [[ -s "$output" ]] || fail "$DEMO_URL$path returned an empty response"
  log "PASS: $path"
done

INDEX_RESPONSE="$WORK_DIR/_index_html"
[[ -s "$INDEX_RESPONSE" ]] || fail "Downloaded index response was not found: $INDEX_RESPONSE"
grep -Fq 'Proud Pops' "$INDEX_RESPONSE" || fail "Demo homepage content validation failed."

SUCCESS=1
log ""
log "SUCCESS: Proud Pops demo deployed from GitHub to the isolated AWS account."
log "Demo URL: $DEMO_URL"
log "AWS account: $EXPECTED_AWS_ACCOUNT"
log "GitHub branch: $GITHUB_BRANCH"
log "GitHub commit: $CLONED_COMMIT"
log "S3 bucket: $BUCKET_NAME"
log "CloudFront distribution: $DISTRIBUTION_ID"
log "Local state: $STATE_FILE"
