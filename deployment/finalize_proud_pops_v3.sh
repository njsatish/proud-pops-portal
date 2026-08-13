#!/bin/bash
set -euo pipefail

INFRA_PROFILE="${INFRA_PROFILE:-default}"
DNS_PROFILE="${DNS_PROFILE:-denduluru}"
HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-Z21S238SFANDPM}"
DOMAIN="${DOMAIN:-proudpops.denduluru.com}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="$REPO_ROOT/deployment/proud-pops-aws-state.env"

[[ -f "$STATE_FILE" ]] || { echo "ERROR: Missing $STATE_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$STATE_FILE"

printf '\n=========================================\n'
printf 'PROUD POPS V3 FINAL VERIFICATION\n'
printf '=========================================\n'

printf '\nWaiting for CloudFront distribution %s...\n' "$DISTRIBUTION_ID"
aws cloudfront wait distribution-deployed \
  --profile "$INFRA_PROFILE" \
  --id "$DISTRIBUTION_ID"

STATUS="$(aws cloudfront get-distribution --profile "$INFRA_PROFILE" --id "$DISTRIBUTION_ID" --query 'Distribution.Status' --output text)"
ENABLED="$(aws cloudfront get-distribution --profile "$INFRA_PROFILE" --id "$DISTRIBUTION_ID" --query 'Distribution.DistributionConfig.Enabled' --output text)"
ALIAS="$(aws cloudfront get-distribution --profile "$INFRA_PROFILE" --id "$DISTRIBUTION_ID" --query 'Distribution.DistributionConfig.Aliases.Items[0]' --output text)"
CERT_STATUS="$(aws acm describe-certificate --profile "$INFRA_PROFILE" --region us-east-1 --certificate-arn "$CERTIFICATE_ARN" --query 'Certificate.Status' --output text)"

printf 'CloudFront status: %s\n' "$STATUS"
printf 'CloudFront enabled: %s\n' "$ENABLED"
printf 'CloudFront alias: %s\n' "$ALIAS"
printf 'Certificate status: %s\n' "$CERT_STATUS"

printf '\nRoute 53 records:\n'
aws route53 list-resource-record-sets \
  --profile "$DNS_PROFILE" \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --query "ResourceRecordSets[?Name=='${DOMAIN}.'].[Type,AliasTarget.DNSName]" \
  --output table

printf '\nDNS resolution:\n'
if command -v dig >/dev/null; then
  dig @1.1.1.1 "$DOMAIN" +short || true
else
  nslookup "$DOMAIN" || true
fi

printf '\nHTTPS check:\n'
HTTP_CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' --connect-timeout 15 "https://$DOMAIN")"
printf 'HTTP status: %s\n' "$HTTP_CODE"
[[ "$HTTP_CODE" == "200" ]] || { echo "ERROR: Expected HTTP 200."; exit 1; }

printf '\nBooksy link check in deployed HTML:\n'
if curl -L -sS "https://$DOMAIN" | grep -q 'booksy.com/en-us/212027_proud-pops-barbershop'; then
  echo 'Booksy link: present'
else
  echo 'ERROR: Booksy link not found in deployed page.'
  exit 1
fi

GITIGNORE="$REPO_ROOT/.gitignore"
touch "$GITIGNORE"
grep -qxF 'deployment/proud-pops-aws-state.env' "$GITIGNORE" || echo 'deployment/proud-pops-aws-state.env' >> "$GITIGNORE"
grep -qxF '.DS_Store' "$GITIGNORE" || echo '.DS_Store' >> "$GITIGNORE"

printf '\nV3 verification passed.\n'
printf 'Website: https://%s\n' "$DOMAIN"
printf '\nRecommended Git commands:\n'
printf '  cd "%s"\n' "$REPO_ROOT"
printf '  git add public-site deployment/deploy_proud_pops_v3_cross_account.sh deployment/finalize_proud_pops_v3.sh .gitignore\n'
printf '  git commit -m "Complete Proud Pops V3 AWS deployment"\n'
printf '  git push origin main\n'
