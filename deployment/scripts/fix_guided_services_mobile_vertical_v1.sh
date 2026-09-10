#!/usr/bin/env bash
set -euo pipefail

EXPECTED_BRANCH="${EXPECTED_BRANCH:-proud-pops-v1}"
EXPECTED_AWS_ACCOUNT="${PROUDPOPS_AWS_ACCOUNT:-460425809139}"
AWS_PROFILE_NAME="${PROUDPOPS_AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
REPO="${1:-$HOME/Downloads/proud-pops-portal}"
PUBLIC_SITE="$REPO/public-site"
SERVICES_HTML="$PUBLIC_SITE/services.html"
SERVICES_CSS="$PUBLIC_SITE/assets/css/services.css"
SITE_CSS="$PUBLIC_SITE/assets/css/site.css"
STATE_FILE="$REPO/deployment/proud-pops-aws-state.env"
COMMIT_MESSAGE="Fix Guided Services mobile vertical layout"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/guided-services-mobile-vertical-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

if [[ -s "$SERVICES_CSS" ]] && grep -Fq 'PROUDPOPS-GUIDED-SERVICE-SELECTOR-V1' "$SERVICES_CSS"; then
  CSS_FILE="$SERVICES_CSS"
  CSS_GIT_PATH="public-site/assets/css/services.css"
  CSS_S3_KEY="assets/css/services.css"
  CSS_URL_PATH="/assets/css/services.css"
else
  CSS_FILE="$SITE_CSS"
  CSS_GIT_PATH="public-site/assets/css/site.css"
  CSS_S3_KEY="assets/css/site.css"
  CSS_URL_PATH="/assets/css/site.css"
fi

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }

restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  log "Restoring previous live stylesheet..."
  aws_cmd s3 cp "$BACKUP_DIR/s3-css-before.css" "s3://$BUCKET_NAME/$CSS_S3_KEY" \
    --content-type 'text/css; charset=utf-8' \
    --cache-control 'public,max-age=300,must-revalidate' >/dev/null || true
  id="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
    --paths "$CSS_URL_PATH" '/services.html' --query 'Invalidation.Id' --output text 2>/dev/null || true)"
  [[ -z "$id" || "$id" == "None" ]] || aws_cmd cloudfront wait invalidation-completed \
    --distribution-id "$DISTRIBUTION_ID" --id "$id" 2>/dev/null || true
}

cleanup(){
  local code=$?
  trap - EXIT INT TERM
  if [[ "$SUCCESS" -ne 1 && "$code" -ne 0 ]]; then restore_live; fi
  rm -rf "$WORK_DIR"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

log "=== Proud Pops Guided Services Mobile Vertical Fix V1 ==="
log "Stylesheet selected: $CSS_FILE"
log "Mobile layout: five vertical service choices, no horizontal overflow"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$SERVICES_HTML" ]] || fail "Services page is missing: $SERVICES_HTML"
[[ -s "$CSS_FILE" ]] || fail "Guided Selector stylesheet is missing."
[[ -f "$STATE_FILE" ]] || fail "AWS deployment state is missing: $STATE_FILE"

grep -Fq -- 'data-guided-services' "$SERVICES_HTML" || fail "Guided Service Selector markup is missing."
grep -Fq -- 'data-service-tab="haircut"' "$SERVICES_HTML" || fail "Haircut service tab is missing."
grep -Fq -- 'data-service-tab="edgeup"' "$SERVICES_HTML" || fail "Edgeup service tab is missing."
grep -Fq -- 'PROUDPOPS-GUIDED-SERVICE-SELECTOR-V1' "$CSS_FILE" || fail "Guided Selector CSS is missing from the selected stylesheet."

cd "$REPO"
BRANCH="$(git branch --show-current)"
[[ "$BRANCH" == "$EXPECTED_BRANCH" ]] || fail "Current branch is '$BRANCH'; expected '$EXPECTED_BRANCH'."
[[ -z "$(git status --porcelain)" ]] || { git status --short; fail "Repository has uncommitted changes."; }
git fetch origin "$BRANCH"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$BRANCH")" ]] || fail "Local branch and origin/$BRANCH differ."

ACCOUNT="$(aws_cmd sts get-caller-identity --query Account --output text)"
[[ "$ACCOUNT" == "$EXPECTED_AWS_ACCOUNT" ]] || fail "Wrong AWS account: $ACCOUNT"
BUCKET_NAME="$(read_state BUCKET_NAME)"
DISTRIBUTION_ID="$(read_state DISTRIBUTION_ID)"
[[ -n "$BUCKET_NAME" && -n "$DISTRIBUTION_ID" ]] || fail "AWS deployment state is incomplete."

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cp "$CSS_FILE" "$BACKUP_DIR/repository-css-before.css"
aws_cmd s3 cp "s3://$BUCKET_NAME/$CSS_S3_KEY" "$BACKUP_DIR/s3-css-before.css" --only-show-errors
[[ -s "$BACKUP_DIR/s3-css-before.css" ]] || fail "Could not back up the deployed stylesheet."
chmod 600 "$BACKUP_DIR"/*

python3 - "$CSS_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
css = path.read_text(encoding='utf-8')
css = re.sub(
    r'\n?/\* PROUDPOPS-GUIDED-SERVICES-MOBILE-VERTICAL-V1 \*/.*?'
    r'/\* PROUDPOPS-GUIDED-SERVICES-MOBILE-VERTICAL-V1-END \*/\n?',
    '\n',
    css,
    flags=re.S,
)
css += r'''

/* PROUDPOPS-GUIDED-SERVICES-MOBILE-VERTICAL-V1 */
@media (max-width: 760px) {
  body,
  .pp-site-main,
  .pp-guided-services,
  .pp-service-choice-wrap,
  .pp-service-detail-wrap,
  .pp-service-detail {
    max-width: 100%;
    min-width: 0;
  }

  .pp-guided-services {
    width: 100%;
    display: grid;
    grid-template-columns: minmax(0,1fr);
    gap: 16px;
    overflow: visible;
  }

  .pp-service-choice-wrap {
    position: static;
    width: 100%;
    padding: 14px;
    overflow: visible;
  }

  .pp-service-choice-heading {
    display: block;
    margin-bottom: 12px;
  }

  .pp-service-choice-heading h2 {
    margin-bottom: 0;
    font-size: 22px;
  }

  .pp-service-choice-list {
    width: 100%;
    display: grid;
    grid-template-columns: minmax(0,1fr);
    gap: 8px;
    overflow: visible;
    padding: 0;
  }

  .pp-service-choice {
    width: 100%;
    min-width: 0;
    padding: 13px 14px;
    display: grid;
    grid-template-columns: minmax(0,1fr) auto;
    align-items: center;
    gap: 12px;
    white-space: normal;
  }

  .pp-service-choice span,
  .pp-service-choice small {
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .pp-service-choice small {
    text-align: right;
    white-space: nowrap;
  }

  .pp-service-choice.is-active {
    box-shadow: inset 4px 0 0 var(--pp-logo-blue,#49a9d7);
  }

  .pp-service-detail-wrap,
  .pp-service-detail {
    width: 100%;
    overflow: hidden;
  }

  .pp-service-detail {
    min-height: 0;
    padding: 22px 18px;
  }

  .pp-service-detail-head {
    width: 100%;
    display: grid;
    grid-template-columns: minmax(0,1fr);
    gap: 18px;
  }

  .pp-service-detail-head > div,
  .pp-service-detail-head h2,
  .pp-service-detail-head p {
    max-width: 100%;
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .pp-service-detail-head h2 {
    font-size: clamp(38px,12vw,50px);
  }

  .pp-service-detail-price {
    font-size: 54px;
  }

  .pp-service-detail-facts {
    width: 100%;
    grid-template-columns: minmax(0,1fr);
    gap: 10px;
  }

  .pp-service-detail-facts div {
    width: 100%;
    min-width: 0;
    min-height: 86px;
    overflow-wrap: anywhere;
  }

  .pp-service-detail-actions {
    width: 100%;
    display: grid;
  }

  .pp-service-detail-actions .pp-button {
    width: 100%;
  }

  /* Keep page content clear of the fixed Contact/Book bar. */
  body:not(.pp-book-page) .pp-site-footer {
    padding-bottom: 118px;
  }
}

@media (max-width: 380px) {
  .pp-service-choice {
    grid-template-columns: 1fr;
  }

  .pp-service-choice small {
    text-align: left;
    white-space: normal;
  }
}
/* PROUDPOPS-GUIDED-SERVICES-MOBILE-VERTICAL-V1-END */
'''
path.write_text('\n'.join(line.rstrip() for line in css.splitlines()).rstrip() + '\n', encoding='utf-8')
PY

log ""
log "=== Validating vertical mobile selector CSS ==="
for required in \
  'PROUDPOPS-GUIDED-SERVICES-MOBILE-VERTICAL-V1' \
  '@media (max-width: 760px)' \
  '.pp-service-choice-list' \
  'grid-template-columns: minmax(0,1fr)' \
  '.pp-service-choice small' \
  'overflow-wrap: anywhere' \
  'padding-bottom: 118px'
do
  grep -Fq -- "$required" "$CSS_FILE" || fail "Stylesheet validation missing: $required"
done

git diff --check || fail "Git whitespace validation failed."
git add -- "$CSS_GIT_PATH"
git diff --cached --quiet && fail "No mobile layout change was staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"
COMMIT_ID="$(git rev-parse --short HEAD)"

log ""
log "=== Publishing vertical mobile Services layout ==="
aws_cmd s3 cp "$CSS_FILE" "s3://$BUCKET_NAME/$CSS_S3_KEY" \
  --content-type 'text/css; charset=utf-8' --cache-control 'public,max-age=300,must-revalidate'
LIVE_REPLACED=1
INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths "$CSS_URL_PATH" '/services.html' --query 'Invalidation.Id' --output text)"
log "CloudFront invalidation: $INVALIDATION_ID"
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

log ""
log "=== Verifying live vertical mobile Services assets ==="
CSS_CODE="$(curl -sS -L -o "$WORK_DIR/services.css" -w '%{http_code}' "https://proudpops.denduluru.com$CSS_URL_PATH?v=$COMMIT_ID-$STAMP")"
HTML_CODE="$(curl -sS -L -o "$WORK_DIR/services.html" -w '%{http_code}' "https://proudpops.denduluru.com/services.html?v=$COMMIT_ID-$STAMP")"
[[ "$CSS_CODE" == "200" && "$HTML_CODE" == "200" ]] || fail "Live Services assets did not return HTTP 200."
for required in \
  'PROUDPOPS-GUIDED-SERVICES-MOBILE-VERTICAL-V1' \
  'grid-template-columns: minmax(0,1fr)' \
  'padding-bottom: 118px'
do
  grep -Fq -- "$required" "$WORK_DIR/services.css" || fail "Live stylesheet is missing: $required"
done
for id in haircut beard-trim shave haircut-with-enhancement edgeup; do
  grep -Fq -- "data-service-tab=\"$id\"" "$WORK_DIR/services.html" || fail "Live Services page is missing $id."
done

for page in /index.html /book.html /about.html /gallery.html /contact.html; do
  code="$(curl -sS -L -o /dev/null -w '%{http_code}' "https://proudpops.denduluru.com$page?protected=$STAMP")"
  [[ "$code" == "200" ]] || fail "$page returned HTTP $code."
done

log ""
log "=== Pushing verified mobile Services fix ==="
if ! git push origin "$BRANCH"; then
  LIVE_REPLACED=0
  fail "Production verified but Git push failed. Retry: git push origin $BRANCH"
fi
LIVE_REPLACED=0
SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean after deployment."

log ""
log "SUCCESS: Guided Services now use a vertical mobile layout."
log "Commit: $COMMIT_ID"
log "Stylesheet: $CSS_URL_PATH"
log "Backup: $BACKUP_DIR"
