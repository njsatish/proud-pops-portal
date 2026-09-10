#!/usr/bin/env bash
set -euo pipefail

EXPECTED_BRANCH="${EXPECTED_BRANCH:-proud-pops-v1}"
EXPECTED_AWS_ACCOUNT="${PROUDPOPS_AWS_ACCOUNT:-460425809139}"
AWS_PROFILE_NAME="${PROUDPOPS_AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
REPO="${1:-$HOME/Downloads/proud-pops-portal}"
SITE_CSS="$REPO/public-site/assets/css/site.css"
STATE_FILE="$REPO/deployment/proud-pops-aws-state.env"
COMMIT_MESSAGE="Remove duplicate mobile hero booking action"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/mobile-hero-book-cleanup-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }

restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  log "Restoring previous live site.css..."
  aws_cmd s3 cp "$BACKUP_DIR/s3-site-before.css" \
    "s3://$BUCKET_NAME/assets/css/site.css" \
    --content-type 'text/css; charset=utf-8' \
    --cache-control 'public,max-age=300,must-revalidate' >/dev/null || true
  rollback_id="$(aws_cmd cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" \
    --paths '/assets/css/site.css' \
    --query 'Invalidation.Id' --output text 2>/dev/null || true)"
  if [[ -n "$rollback_id" && "$rollback_id" != "None" ]]; then
    aws_cmd cloudfront wait invalidation-completed \
      --distribution-id "$DISTRIBUTION_ID" --id "$rollback_id" 2>/dev/null || true
  fi
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

log "=== Proud Pops Mobile Hero Booking Cleanup V1 ==="
log "Mobile: hide hero Book Now, retain persistent Book Appointment"
log "Desktop: retain hero Book Now"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$SITE_CSS" ]] || fail "Shared site.css is missing."
[[ -s "$REPO/public-site/index.html" ]] || fail "index.html is missing."
[[ -f "$STATE_FILE" ]] || fail "AWS state file is missing."

grep -Fq -- 'pp-concept-home-actions' "$REPO/public-site/index.html" || fail "Homepage hero actions are missing."
grep -Fq -- 'pp-mobile-book' "$REPO/public-site/index.html" || fail "Persistent mobile booking action is missing."

cd "$REPO"
BRANCH="$(git branch --show-current)"
[[ "$BRANCH" == "$EXPECTED_BRANCH" ]] || fail "Current branch is '$BRANCH'; expected '$EXPECTED_BRANCH'."
[[ -z "$(git status --porcelain)" ]] || { git status --short; fail "Repository has uncommitted changes."; }
git fetch origin "$BRANCH"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$BRANCH")" ]] || fail "Local branch and origin/$BRANCH differ."

ACTUAL_ACCOUNT="$(aws_cmd sts get-caller-identity --query Account --output text)"
[[ "$ACTUAL_ACCOUNT" == "$EXPECTED_AWS_ACCOUNT" ]] || fail "Wrong AWS account: $ACTUAL_ACCOUNT"
BUCKET_NAME="$(read_state BUCKET_NAME)"
DISTRIBUTION_ID="$(read_state DISTRIBUTION_ID)"
[[ -n "$BUCKET_NAME" && -n "$DISTRIBUTION_ID" ]] || fail "AWS deployment state is incomplete."

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cp "$SITE_CSS" "$BACKUP_DIR/repository-site-before.css"
aws_cmd s3 cp "s3://$BUCKET_NAME/assets/css/site.css" \
  "$BACKUP_DIR/s3-site-before.css" --only-show-errors
[[ -s "$BACKUP_DIR/s3-site-before.css" ]] || fail "Could not back up deployed site.css."
chmod 600 "$BACKUP_DIR"/*.css

python3 - "$SITE_CSS" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
css = path.read_text(encoding="utf-8")
css = re.sub(
    r"\n?/\* PROUDPOPS-MOBILE-SINGLE-BOOKING-ACTION-V1 \*/.*?"
    r"/\* PROUDPOPS-MOBILE-SINGLE-BOOKING-ACTION-V1-END \*/\n?",
    "\n",
    css,
    flags=re.S,
)

css = css.rstrip() + r'''

/* PROUDPOPS-MOBILE-SINGLE-BOOKING-ACTION-V1 */
@media (max-width: 760px) {
  /* The persistent bottom Book Appointment action is already visible, so the
     matching hero booking action is hidden to avoid duplicate CTAs. */
  .pp-concept-home-actions .pp-button-primary[href="/book.html"] {
    display: none;
  }

  .pp-concept-home-actions {
    display: block;
  }

  .pp-concept-home-actions .pp-button-secondary {
    width: 100%;
  }
}
/* PROUDPOPS-MOBILE-SINGLE-BOOKING-ACTION-V1-END */
'''

path.write_text("\n".join(line.rstrip() for line in css.splitlines()).rstrip() + "\n", encoding="utf-8")
PY

log ""
log "=== Validating mobile booking cleanup ==="
for required in \
  'PROUDPOPS-MOBILE-SINGLE-BOOKING-ACTION-V1' \
  '@media (max-width: 760px)' \
  '.pp-concept-home-actions .pp-button-primary[href="/book.html"]' \
  'display: none' \
  '.pp-concept-home-actions .pp-button-secondary' \
  'width: 100%'
do
  grep -Fq -- "$required" "$SITE_CSS" || fail "site.css validation missing: $required"
done

git diff --check || fail "Git whitespace validation failed."
git add -- public-site/assets/css/site.css
git diff --cached --quiet && fail "No mobile booking cleanup was staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"
COMMIT_ID="$(git rev-parse --short HEAD)"

log ""
log "=== Publishing mobile booking cleanup ==="
aws_cmd s3 cp "$SITE_CSS" "s3://$BUCKET_NAME/assets/css/site.css" \
  --content-type 'text/css; charset=utf-8' \
  --cache-control 'public,max-age=300,must-revalidate'
LIVE_REPLACED=1

INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths '/assets/css/site.css' \
  --query 'Invalidation.Id' --output text)"
log "CloudFront invalidation: $INVALIDATION_ID"
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

log ""
log "=== Verifying live mobile booking cleanup ==="
CSS_CODE="$(curl -sS -L -o "$WORK_DIR/site.css" -w '%{http_code}' "https://proudpops.denduluru.com/assets/css/site.css?v=$COMMIT_ID-$STAMP")"
HOME_CODE="$(curl -sS -L -o "$WORK_DIR/index.html" -w '%{http_code}' "https://proudpops.denduluru.com/?mobile-book=$STAMP")"
[[ "$CSS_CODE" == "200" ]] || fail "Live site.css returned HTTP $CSS_CODE."
[[ "$HOME_CODE" == "200" ]] || fail "Homepage returned HTTP $HOME_CODE."
for required in \
  'PROUDPOPS-MOBILE-SINGLE-BOOKING-ACTION-V1' \
  '.pp-concept-home-actions .pp-button-primary[href="/book.html"]' \
  'display: none'
do
  grep -Fq -- "$required" "$WORK_DIR/site.css" || fail "Live site.css is missing: $required"
done

grep -Fq -- 'pp-concept-home-actions' "$WORK_DIR/index.html" || fail "Live hero actions are missing."
grep -Fq -- 'pp-mobile-book' "$WORK_DIR/index.html" || fail "Live persistent booking action is missing."
grep -Fq -- 'About Proud Pops' "$WORK_DIR/index.html" || fail "Live About action is missing."

for page in /book.html /services.html /about.html /gallery.html /contact.html; do
  code="$(curl -sS -L -o /dev/null -w '%{http_code}' "https://proudpops.denduluru.com$page?protected=$STAMP")"
  [[ "$code" == "200" ]] || fail "$page returned HTTP $code."
done

log ""
log "=== Pushing verified mobile cleanup commit ==="
if ! git push origin "$BRANCH"; then
  log "ERROR: Mobile cleanup is verified in production, but Git push failed."
  log "Retry: cd '$REPO' && git push origin '$BRANCH'"
  LIVE_REPLACED=0
  exit 1
fi

LIVE_REPLACED=0
SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean after deployment."

log ""
log "SUCCESS: Duplicate mobile hero booking action removed."
log "Commit: $COMMIT_ID"
log "Mobile keeps: About Proud Pops and persistent Book Appointment"
log "Desktop keeps: Book Now and About Proud Pops"
log "Backup: $BACKUP_DIR"
