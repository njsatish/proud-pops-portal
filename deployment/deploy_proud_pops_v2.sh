#!/bin/bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
BUCKET_NAME="${BUCKET_NAME:-proudpops-denduluru-demo}"
DISTRIBUTION_ID="${DISTRIBUTION_ID:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="$REPO_ROOT/public-site"
BACKUP_DIR="$REPO_ROOT/backups/proud-pops-v2-$(date -u +%Y%m%dT%H%M%SZ)"

printf '\n=========================================\n'
printf 'PROUD POPS V2 AWS DEPLOYMENT\n'
printf '=========================================\n'
printf 'Repository: %s\nBucket: %s\nRegion: %s\n\n' "$REPO_ROOT" "$BUCKET_NAME" "$AWS_REGION"

command -v aws >/dev/null || { echo "ERROR: AWS CLI is not installed."; exit 1; }
aws sts get-caller-identity >/dev/null
[[ -f "$SITE_DIR/index.html" ]] || { echo "ERROR: $SITE_DIR/index.html is missing."; exit 1; }

if ! aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  echo "Creating private S3 bucket..."
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" >/dev/null
fi

echo "Enforcing S3 Block Public Access..."
aws s3api put-public-access-block --bucket "$BUCKET_NAME" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Creating a local deployment backup..."
mkdir -p "$BACKUP_DIR"
cp -R "$SITE_DIR"/. "$BACKUP_DIR"/

echo "Uploading V2 site files..."
aws s3 sync "$SITE_DIR/" "s3://$BUCKET_NAME/" --delete \
  --exclude ".DS_Store" --exclude "*.sh" \
  --cache-control "public,max-age=300"
aws s3 cp "$SITE_DIR/index.html" "s3://$BUCKET_NAME/index.html" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "no-cache,no-store,must-revalidate"

if [[ -n "$DISTRIBUTION_ID" ]]; then
  echo "Invalidating CloudFront distribution $DISTRIBUTION_ID..."
  aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "/*"
else
  echo "CloudFront invalidation skipped: no Proud Pops distribution exists yet."
  echo "Later run: DISTRIBUTION_ID=YOUR_ID ./deployment/deploy_proud_pops_v2.sh"
fi

printf '\nV2 upload complete.\n'
printf 'S3 bucket: s3://%s\n' "$BUCKET_NAME"
printf 'Local backup: %s\n' "$BACKUP_DIR"
printf 'Note: CloudFront OAC, ACM, and Route 53 still need to be created for proudpops.denduluru.com.\n'
