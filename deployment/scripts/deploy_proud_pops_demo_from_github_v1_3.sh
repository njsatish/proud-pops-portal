#!/usr/bin/env bash
set -euo pipefail

EXPECTED_ACCOUNT="${PROUDPOPS_DEMO_AWS_ACCOUNT:-019051663952}"
EXPECTED_ARN="${PROUDPOPS_DEMO_EXPECTED_ARN:-arn:aws:iam::019051663952:user/karthik}"
AWS_PROFILE_NAME="${PROUDPOPS_DEMO_AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
DISTRIBUTION_ID="${PROUDPOPS_DEMO_DISTRIBUTION_ID:-EQZY7LNUTOMS0}"
EXPECTED_DOMAIN="${PROUDPOPS_DEMO_DOMAIN:-dzytjy44i8ren.cloudfront.net}"
BUCKET_NAME="${PROUDPOPS_DEMO_BUCKET:-proud-pops-demo-019051663952-us-east-1}"
OAC_NAME="${PROUDPOPS_DEMO_OAC:-proud-pops-demo-oac-019051663952}"
GITHUB_BRANCH="${PROUDPOPS_GITHUB_BRANCH:-proud-pops-v1}"
REPO="${1:-$(pwd)}"
BASE_SCRIPT="$REPO/deployment/scripts/deploy_proud_pops_demo_from_github_v1_1.sh"
STATE_DIR="${PROUDPOPS_DEMO_STATE_DIR:-$HOME/.config/proud-pops-demo}"
STATE_FILE="$STATE_DIR/aws-state.env"
TEMP_SCRIPT="$(mktemp)"

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }
cleanup(){ rm -f "$TEMP_SCRIPT"; }
trap cleanup EXIT INT TERM

log "=== Proud Pops Demo Deployment V1.3 ==="
log "Authorized identity: $EXPECTED_ARN"
log "Existing distribution: $DISTRIBUTION_ID"
log "Existing domain: $EXPECTED_DOMAIN"

for command in aws git sed bash; do command -v "$command" >/dev/null 2>&1 || fail "$command is required."; done
[[ -d "$REPO/.git" ]] || fail "Run this from the proud-pops-portal repository."
[[ -s "$BASE_SCRIPT" ]] || fail "Base V1.1 script is missing: $BASE_SCRIPT"

ACTUAL_ACCOUNT="$(aws_cmd sts get-caller-identity --query Account --output text)"
ACTUAL_ARN="$(aws_cmd sts get-caller-identity --query Arn --output text)"
[[ "$ACTUAL_ACCOUNT" == "$EXPECTED_ACCOUNT" ]] || fail "Wrong AWS account: $ACTUAL_ACCOUNT"
[[ "$ACTUAL_ARN" == "$EXPECTED_ARN" ]] || fail "Wrong AWS identity: $ACTUAL_ARN; expected $EXPECTED_ARN"
log "PASS AWS identity: $ACTUAL_ARN"

ACTUAL_DOMAIN="$(aws_cmd cloudfront get-distribution --id "$DISTRIBUTION_ID" --query 'Distribution.DomainName' --output text)"
[[ "$ACTUAL_DOMAIN" == "$EXPECTED_DOMAIN" ]] || fail "Unexpected CloudFront domain: $ACTUAL_DOMAIN"
log "PASS existing CloudFront distribution: $DISTRIBUTION_ID"
aws_cmd s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1 || fail "Existing S3 bucket unavailable: $BUCKET_NAME"
log "PASS existing S3 bucket: $BUCKET_NAME"
OAC_ID="$(aws_cmd cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='$OAC_NAME'].Id | [0]" --output text)"
[[ -n "$OAC_ID" && "$OAC_ID" != "None" ]] || fail "Existing OAC not found: $OAC_NAME"
log "PASS existing OAC: $OAC_ID"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
cat > "$STATE_FILE" <<STATE
AWS_ACCOUNT=$EXPECTED_ACCOUNT
AWS_PROFILE=$AWS_PROFILE_NAME
AWS_REGION=$REGION
GITHUB_REPO=https://github.com/njsatish/proud-pops-portal.git
GITHUB_BRANCH=$GITHUB_BRANCH
GITHUB_COMMIT=$(git -C "$REPO" rev-parse HEAD)
BUCKET_NAME=$BUCKET_NAME
OAC_ID=$OAC_ID
DISTRIBUTION_ID=$DISTRIBUTION_ID
STATE
chmod 600 "$STATE_FILE"
log "PASS local demo state: $STATE_FILE"

IAM_USERNAME="${EXPECTED_ARN##*/}"
sed "s|:user/proud-pops-demo-deployer|:user/$IAM_USERNAME|g" "$BASE_SCRIPT" > "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"
bash -n "$TEMP_SCRIPT"
grep -Fq ":user/$IAM_USERNAME" "$TEMP_SCRIPT" || fail "Could not authorize expected IAM username in temporary script."
log "PASS temporary deployment authorization: $IAM_USERNAME"

PROUDPOPS_DEMO_AWS_PROFILE="$AWS_PROFILE_NAME" PROUDPOPS_DEMO_AWS_ACCOUNT="$EXPECTED_ACCOUNT" AWS_REGION="$REGION" PROUDPOPS_GITHUB_BRANCH="$GITHUB_BRANCH" PROUDPOPS_DEMO_STATE_DIR="$STATE_DIR" "$TEMP_SCRIPT"

log ""
log "SUCCESS: Karthik deployed to the existing Proud Pops demo infrastructure."
log "Demo URL: https://$EXPECTED_DOMAIN"
log "Distribution: $DISTRIBUTION_ID"
log "Bucket: $BUCKET_NAME"
