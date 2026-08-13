#!/bin/bash
set -euo pipefail
INFRA_PROFILE="${INFRA_PROFILE:-default}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/deployment/proud-pops-aws-state.env"
aws s3 sync "$ROOT/public-site/" "s3://$BUCKET_NAME/" --profile "$INFRA_PROFILE" --delete --exclude '.DS_Store' --cache-control 'public,max-age=86400'
aws s3 cp "$ROOT/public-site/index.html" "s3://$BUCKET_NAME/index.html" --profile "$INFRA_PROFILE" --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate'
ID="$(aws cloudfront create-invalidation --profile "$INFRA_PROFILE" --distribution-id "$DISTRIBUTION_ID" --paths '/*' --query 'Invalidation.Id' --output text)"
aws cloudfront wait invalidation-completed --profile "$INFRA_PROFILE" --distribution-id "$DISTRIBUTION_ID" --id "$ID"
CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' "https://$DOMAIN")"
echo "Proud Pops V4: https://$DOMAIN (HTTP $CODE)"
[[ "$CODE" == 200 ]]
