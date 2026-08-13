#!/bin/bash
set -euo pipefail
PROFILE="${INFRA_PROFILE:-default}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/deployment/proud-pops-aws-state.env"
[[ -f "$STATE" ]] || { echo "ERROR: Missing $STATE"; exit 1; }
source "$STATE"
aws s3 sync "$ROOT/public-site/" "s3://$BUCKET_NAME/" --profile "$PROFILE" --delete --exclude '.DS_Store' --cache-control 'public,max-age=86400'
aws s3 cp "$ROOT/public-site/index.html" "s3://$BUCKET_NAME/index.html" --profile "$PROFILE" --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate'
ID="$(aws cloudfront create-invalidation --profile "$PROFILE" --distribution-id "$DISTRIBUTION_ID" --paths '/*' --query 'Invalidation.Id' --output text)"
aws cloudfront wait invalidation-completed --profile "$PROFILE" --distribution-id "$DISTRIBUTION_ID" --id "$ID"
CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' "https://$DOMAIN")"
echo "Proud Pops V7: https://$DOMAIN (HTTP $CODE)"
[[ "$CODE" == 200 ]]
