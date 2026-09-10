#!/usr/bin/env bash
set -euo pipefail

EXPECTED_BRANCH="${EXPECTED_BRANCH:-proud-pops-v1}"
EXPECTED_AWS_ACCOUNT="${PROUDPOPS_AWS_ACCOUNT:-460425809139}"
AWS_PROFILE_NAME="${PROUDPOPS_AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
REPO="${1:-$HOME/Downloads/proud-pops-portal}"
PUBLIC_SITE="$REPO/public-site"
BOOK_HTML="$PUBLIC_SITE/book.html"
SITE_CSS="$PUBLIC_SITE/assets/css/site.css"
STATE_FILE="$REPO/deployment/proud-pops-aws-state.env"
COMMIT_MESSAGE="Hide redundant mobile booking bar on Book page"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/mobile-book-page-bar-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }

restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  log "Restoring previous live Book page and shared CSS..."
  aws_cmd s3 cp "$BACKUP_DIR/s3-book-before.html" \
    "s3://$BUCKET_NAME/book.html" \
    --content-type 'text/html; charset=utf-8' \
    --cache-control 'no-cache,no-store,must-revalidate' >/dev/null || true
  aws_cmd s3 cp "$BACKUP_DIR/s3-site-before.css" \
    "s3://$BUCKET_NAME/assets/css/site.css" \
    --content-type 'text/css; charset=utf-8' \
    --cache-control 'public,max-age=300,must-revalidate' >/dev/null || true

  rollback_id="$(aws_cmd cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" \
    --paths '/book.html' '/assets/css/site.css' \
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

log "=== Proud Pops Mobile Book-Page Bar Cleanup V1 ==="
log "Mobile Book page: hide fixed Contact / Book Appointment bar"
log "Mobile Book page: keep Confirm Availability in Booksy"
log "Other pages and desktop: unchanged"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$BOOK_HTML" ]] || fail "book.html is missing."
[[ -s "$SITE_CSS" ]] || fail "site.css is missing."
[[ -f "$STATE_FILE" ]] || fail "AWS state file is missing."
command -v python3 >/dev/null 2>&1 || fail "python3 is required."

grep -Fq -- 'data-booking-root' "$BOOK_HTML" || fail "Book page booking interface is missing."
grep -Fq -- 'data-booking-confirm' "$BOOK_HTML" || fail "Booksy confirmation action is missing."
grep -Fq -- 'pp-mobile-actions' "$BOOK_HTML" || fail "Book page mobile action bar is missing."

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
cp "$BOOK_HTML" "$BACKUP_DIR/repository-book-before.html"
cp "$SITE_CSS" "$BACKUP_DIR/repository-site-before.css"
aws_cmd s3 cp "s3://$BUCKET_NAME/book.html" \
  "$BACKUP_DIR/s3-book-before.html" --only-show-errors
aws_cmd s3 cp "s3://$BUCKET_NAME/assets/css/site.css" \
  "$BACKUP_DIR/s3-site-before.css" --only-show-errors
[[ -s "$BACKUP_DIR/s3-book-before.html" ]] || fail "Could not back up deployed book.html."
[[ -s "$BACKUP_DIR/s3-site-before.css" ]] || fail "Could not back up deployed site.css."
chmod 600 "$BACKUP_DIR"/*

python3 - "$BOOK_HTML" "$SITE_CSS" <<'PY'
from pathlib import Path
import re
import sys

book_path = Path(sys.argv[1])
css_path = Path(sys.argv[2])
book = book_path.read_text(encoding="utf-8")
css = css_path.read_text(encoding="utf-8")

# Add an explicit page class rather than relying on :has(), keeping behavior
# predictable across mobile Safari and other browsers.
body_match = re.search(r'<body(?P<attrs>[^>]*)>', book, re.I)
if not body_match:
    raise SystemExit("ERROR: Book page body tag not found")
attrs = body_match.group("attrs")
class_match = re.search(r'class=["\']([^"\']*)["\']', attrs, re.I)
if class_match:
    classes = class_match.group(1).split()
    if "pp-book-page" not in classes:
        classes.append("pp-book-page")
    new_attrs = re.sub(
        r'class=["\'][^"\']*["\']',
        'class="' + ' '.join(classes) + '"',
        attrs,
        count=1,
        flags=re.I,
    )
else:
    new_attrs = attrs + ' class="pp-book-page"'
book = book[:body_match.start()] + '<body' + new_attrs + '>' + book[body_match.end():]

marker = '<!-- PROUDPOPS-MOBILE-BOOK-PAGE-SINGLE-ACTION-V1 -->'
if marker not in book:
    book = book.replace('</head>', f'  {marker}\n</head>', 1)
book_path.write_text(
    "\n".join(line.rstrip() for line in book.splitlines()).rstrip() + "\n",
    encoding="utf-8",
)

css = re.sub(
    r"\n?/\* PROUDPOPS-MOBILE-BOOK-PAGE-SINGLE-ACTION-V1 \*/.*?"
    r"/\* PROUDPOPS-MOBILE-BOOK-PAGE-SINGLE-ACTION-V1-END \*/\n?",
    "\n",
    css,
    flags=re.S,
)
css = css.rstrip() + r'''

/* PROUDPOPS-MOBILE-BOOK-PAGE-SINGLE-ACTION-V1 */
@media (max-width: 760px) {
  /* Once a customer is on the Book page, Confirm Availability in Booksy is
     the relevant conversion action. The global fixed booking bar is hidden. */
  body.pp-book-page .pp-mobile-actions {
    display: none !important;
  }

  /* Remove space reserved globally for the fixed mobile action bar. */
  body.pp-book-page {
    padding-bottom: 0 !important;
  }

  body.pp-book-page .pp-site-footer {
    padding-bottom: 38px;
  }

  /* Keep the selected appointment confirmation visible and easy to tap. */
  body.pp-book-page [data-booking-confirm] {
    width: 100%;
    min-height: 58px;
  }
}
/* PROUDPOPS-MOBILE-BOOK-PAGE-SINGLE-ACTION-V1-END */
'''
css_path.write_text(
    "\n".join(line.rstrip() for line in css.splitlines()).rstrip() + "\n",
    encoding="utf-8",
)
PY

log ""
log "=== Validating mobile Book-page cleanup ==="
for required in \
  'class="pp-book-page"' \
  'PROUDPOPS-MOBILE-BOOK-PAGE-SINGLE-ACTION-V1' \
  'data-booking-confirm' \
  'pp-mobile-actions'
do
  grep -Fq -- "$required" "$BOOK_HTML" || fail "book.html validation missing: $required"
done

for required in \
  'PROUDPOPS-MOBILE-BOOK-PAGE-SINGLE-ACTION-V1' \
  'body.pp-book-page .pp-mobile-actions' \
  'display: none !important' \
  'body.pp-book-page [data-booking-confirm]' \
  'min-height: 58px'
do
  grep -Fq -- "$required" "$SITE_CSS" || fail "site.css validation missing: $required"
done

git diff --check || fail "Git whitespace validation failed."
git add -- public-site/book.html public-site/assets/css/site.css
git diff --cached --quiet && fail "No mobile Book-page cleanup was staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"
COMMIT_ID="$(git rev-parse --short HEAD)"

log ""
log "=== Publishing focused Book-page mobile cleanup ==="
aws_cmd s3 cp "$BOOK_HTML" "s3://$BUCKET_NAME/book.html" \
  --content-type 'text/html; charset=utf-8' \
  --cache-control 'no-cache,no-store,must-revalidate'
aws_cmd s3 cp "$SITE_CSS" "s3://$BUCKET_NAME/assets/css/site.css" \
  --content-type 'text/css; charset=utf-8' \
  --cache-control 'public,max-age=300,must-revalidate'
LIVE_REPLACED=1

INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths '/book.html' '/assets/css/site.css' \
  --query 'Invalidation.Id' --output text)"
log "CloudFront invalidation: $INVALIDATION_ID"
aws_cmd cloudfront wait invalidation-completed \
  --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

log ""
log "=== Verifying live focused cleanup ==="
BOOK_CODE="$(curl -sS -L -o "$WORK_DIR/book.html" -w '%{http_code}' "https://proudpops.denduluru.com/book.html?v=$COMMIT_ID-$STAMP")"
CSS_CODE="$(curl -sS -L -o "$WORK_DIR/site.css" -w '%{http_code}' "https://proudpops.denduluru.com/assets/css/site.css?v=$COMMIT_ID-$STAMP")"
[[ "$BOOK_CODE" == "200" ]] || fail "Live Book page returned HTTP $BOOK_CODE."
[[ "$CSS_CODE" == "200" ]] || fail "Live site.css returned HTTP $CSS_CODE."

grep -Fq -- 'class="pp-book-page"' "$WORK_DIR/book.html" || fail "Live Book page class is missing."
grep -Fq -- 'data-booking-confirm' "$WORK_DIR/book.html" || fail "Live Booksy confirmation action is missing."
grep -Fq -- 'pp-mobile-actions' "$WORK_DIR/book.html" || fail "Global mobile markup was removed instead of conditionally hidden."
grep -Fq -- 'body.pp-book-page .pp-mobile-actions' "$WORK_DIR/site.css" || fail "Live page-specific hide rule is missing."
grep -Fq -- 'display: none !important' "$WORK_DIR/site.css" || fail "Live mobile hide declaration is missing."

for page in /index.html /services.html /about.html /gallery.html /contact.html; do
  output="$WORK_DIR/$(basename "$page")"
  code="$(curl -sS -L -o "$output" -w '%{http_code}' "https://proudpops.denduluru.com$page?protected=$STAMP")"
  [[ "$code" == "200" ]] || fail "$page returned HTTP $code."
  grep -Fq -- 'pp-mobile-actions' "$output" || fail "$page lost its mobile action bar markup."
  log "PASS protected mobile bar: $page"
done

log ""
log "=== Pushing verified Book-page mobile cleanup ==="
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
log "SUCCESS: Fixed mobile Contact/Book bar hidden on Book page only."
log "Commit: $COMMIT_ID"
log "Book page primary action: Confirm Availability in Booksy"
log "Other pages retain: Contact and Book Appointment bar"
log "Backup: $BACKUP_DIR"
