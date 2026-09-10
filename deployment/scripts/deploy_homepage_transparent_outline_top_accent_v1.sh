#!/usr/bin/env bash
set -euo pipefail

EXPECTED_BRANCH="${EXPECTED_BRANCH:-proud-pops-v1}"
EXPECTED_AWS_ACCOUNT="${PROUDPOPS_AWS_ACCOUNT:-460425809139}"
AWS_PROFILE_NAME="${PROUDPOPS_AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
REPO="${1:-$HOME/Downloads/proud-pops-portal}"
PUBLIC_SITE="$REPO/public-site"
INDEX="$PUBLIC_SITE/index.html"
STAGED_HOME="$PUBLIC_SITE/multipage-index.html"
SITE_CSS="$PUBLIC_SITE/assets/css/site.css"
STATE_FILE="$REPO/deployment/proud-pops-aws-state.env"
COMMIT_MESSAGE="Add transparent outlines and color accents to homepage services"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/home-service-accents-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }

restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  log "Restoring previous live homepages and shared CSS..."
  for file in index.html multipage-index.html; do
    aws_cmd s3 cp "$BACKUP_DIR/s3-$file" "s3://$BUCKET_NAME/$file" \
      --content-type 'text/html; charset=utf-8' \
      --cache-control 'no-cache,no-store,must-revalidate' >/dev/null || true
  done
  aws_cmd s3 cp "$BACKUP_DIR/s3-site.css" "s3://$BUCKET_NAME/assets/css/site.css" \
    --content-type 'text/css; charset=utf-8' \
    --cache-control 'public,max-age=300,must-revalidate' >/dev/null || true
  id="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
    --paths '/' '/index.html' '/multipage-index.html' '/assets/css/site.css' \
    --query 'Invalidation.Id' --output text 2>/dev/null || true)"
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

log "=== Proud Pops Homepage Transparent Outline + Top Accent V1 ==="
log "Design: existing dark service cards with translucent borders and top accents"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$INDEX" ]] || fail "Homepage is missing: $INDEX"
[[ -s "$STAGED_HOME" ]] || fail "Staged homepage is missing: $STAGED_HOME"
[[ -s "$SITE_CSS" ]] || fail "Shared CSS is missing: $SITE_CSS"
[[ -f "$STATE_FILE" ]] || fail "AWS deployment state is missing: $STATE_FILE"

for page in "$INDEX" "$STAGED_HOME"; do
  grep -Fq -- 'Five ways to get' "$page" || fail "Homepage Services heading is missing from $(basename "$page")."
  grep -Fq -- 'Haircut With' "$page" || fail "Five-service markup is missing from $(basename "$page")."
done

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
cp "$INDEX" "$BACKUP_DIR/repository-index.html"
cp "$STAGED_HOME" "$BACKUP_DIR/repository-multipage-index.html"
cp "$SITE_CSS" "$BACKUP_DIR/repository-site.css"
aws_cmd s3 cp "s3://$BUCKET_NAME/index.html" "$BACKUP_DIR/s3-index.html" --only-show-errors
aws_cmd s3 cp "s3://$BUCKET_NAME/multipage-index.html" "$BACKUP_DIR/s3-multipage-index.html" --only-show-errors
aws_cmd s3 cp "s3://$BUCKET_NAME/assets/css/site.css" "$BACKUP_DIR/s3-site.css" --only-show-errors
for backup in "$BACKUP_DIR/s3-index.html" "$BACKUP_DIR/s3-multipage-index.html" "$BACKUP_DIR/s3-site.css"; do
  [[ -s "$backup" ]] || fail "Live backup failed: $backup"
done
chmod 600 "$BACKUP_DIR"/*

python3 - "$INDEX" "$STAGED_HOME" "$SITE_CSS" <<'PY'
from pathlib import Path
import re
import sys

home_paths = [Path(sys.argv[1]), Path(sys.argv[2])]
css_path = Path(sys.argv[3])
marker = '<!-- PROUDPOPS-HOME-SERVICE-ACCENTS-V1 -->'

for path in home_paths:
    text = path.read_text(encoding='utf-8')
    body = re.search(r'<body(?P<attrs>[^>]*)>', text, re.I)
    if not body:
        raise SystemExit(f'ERROR: Body tag missing in {path.name}')
    attrs = body.group('attrs')
    class_match = re.search(r'class=["\']([^"\']*)["\']', attrs, re.I)
    if class_match:
        classes = class_match.group(1).split()
        if 'pp-homepage' not in classes:
            classes.append('pp-homepage')
        new_attrs = re.sub(
            r'class=["\'][^"\']*["\']',
            'class="' + ' '.join(classes) + '"',
            attrs,
            count=1,
            flags=re.I,
        )
    else:
        new_attrs = attrs + ' class="pp-homepage"'
    text = text[:body.start()] + '<body' + new_attrs + '>' + text[body.end():]
    if marker not in text:
        text = text.replace('</head>', f'  {marker}\n</head>', 1)
    path.write_text('\n'.join(line.rstrip() for line in text.splitlines()).rstrip() + '\n', encoding='utf-8')

css = css_path.read_text(encoding='utf-8')
css = re.sub(
    r'\n?/\* PROUDPOPS-HOME-SERVICE-ACCENTS-V1 \*/.*?'
    r'/\* PROUDPOPS-HOME-SERVICE-ACCENTS-V1-END \*/\n?',
    '\n',
    css,
    flags=re.S,
)
css += r'''

/* PROUDPOPS-HOME-SERVICE-ACCENTS-V1 */
/* Preserve the existing card design. Only the outline, top accent, subtle
   tint, and hover feedback change. Multiple class variants are supported so
   the rule remains compatible with the current homepage markup. */
.pp-homepage :is(.pp-concept-service-card,.pp-service-card,.pp-home-service-card) {
  --pp-service-accent: #49a9d7;
  position: relative;
  overflow: hidden;
  border: 1px solid color-mix(in srgb,var(--pp-service-accent) 34%,transparent) !important;
  background:
    linear-gradient(180deg,color-mix(in srgb,var(--pp-service-accent) 5%,transparent),transparent 43%),
    var(--pp-panel,#0d141a) !important;
  box-shadow:
    0 16px 34px rgba(0,0,0,.22),
    0 0 0 1px color-mix(in srgb,var(--pp-service-accent) 5%,transparent);
  transition: transform .18s ease,border-color .18s ease,background .18s ease,box-shadow .18s ease;
}
.pp-homepage :is(.pp-concept-service-card,.pp-service-card,.pp-home-service-card)::before {
  content: "";
  position: absolute;
  z-index: 1;
  inset: 0 0 auto;
  height: 5px;
  background: var(--pp-service-accent);
}
.pp-homepage :is(.pp-concept-service-card,.pp-service-card,.pp-home-service-card):hover {
  border-color: color-mix(in srgb,var(--pp-service-accent) 66%,transparent) !important;
  background:
    linear-gradient(180deg,color-mix(in srgb,var(--pp-service-accent) 10%,transparent),transparent 48%),
    #10181f !important;
  box-shadow:
    0 20px 42px rgba(0,0,0,.28),
    0 0 24px color-mix(in srgb,var(--pp-service-accent) 12%,transparent);
  transform: translateY(-3px);
}
.pp-homepage :is(.pp-concept-service-grid,.pp-services-grid,.pp-home-services-grid)
  > :is(.pp-concept-service-card,.pp-service-card,.pp-home-service-card):nth-child(1) {
  --pp-service-accent: #49a9d7;
}
.pp-homepage :is(.pp-concept-service-grid,.pp-services-grid,.pp-home-services-grid)
  > :is(.pp-concept-service-card,.pp-service-card,.pp-home-service-card):nth-child(2) {
  --pp-service-accent: #2fb5aa;
}
.pp-homepage :is(.pp-concept-service-grid,.pp-services-grid,.pp-home-services-grid)
  > :is(.pp-concept-service-card,.pp-service-card,.pp-home-service-card):nth-child(3) {
  --pp-service-accent: #55c7d9;
}
.pp-homepage :is(.pp-concept-service-grid,.pp-services-grid,.pp-home-services-grid)
  > :is(.pp-concept-service-card,.pp-service-card,.pp-home-service-card):nth-child(4) {
  --pp-service-accent: #798ee8;
}
.pp-homepage :is(.pp-concept-service-grid,.pp-services-grid,.pp-home-services-grid)
  > :is(.pp-concept-service-card,.pp-service-card,.pp-home-service-card):nth-child(5) {
  --pp-service-accent: #66c89a;
}
@media (prefers-reduced-motion: reduce) {
  .pp-homepage :is(.pp-concept-service-card,.pp-service-card,.pp-home-service-card) {
    transition: none;
  }
  .pp-homepage :is(.pp-concept-service-card,.pp-service-card,.pp-home-service-card):hover {
    transform: none;
  }
}
/* PROUDPOPS-HOME-SERVICE-ACCENTS-V1-END */
'''
css_path.write_text('\n'.join(line.rstrip() for line in css.splitlines()).rstrip() + '\n', encoding='utf-8')
PY

log ""
log "=== Validating homepage service accents ==="
for page in "$INDEX" "$STAGED_HOME"; do
  grep -Fq -- 'class="pp-homepage' "$page" || grep -Fq -- ' pp-homepage' "$page" || fail "Homepage body class missing from $(basename "$page")."
  grep -Fq -- 'PROUDPOPS-HOME-SERVICE-ACCENTS-V1' "$page" || fail "Marker missing from $(basename "$page")."
done
for required in \
  'PROUDPOPS-HOME-SERVICE-ACCENTS-V1' \
  'color-mix(in srgb,var(--pp-service-accent) 34%,transparent)' \
  'height: 5px' \
  '#49a9d7' '#2fb5aa' '#55c7d9' '#798ee8' '#66c89a'
do
  grep -Fq -- "$required" "$SITE_CSS" || fail "site.css validation missing: $required"
done

git diff --check || fail "Git whitespace validation failed."
git add -- public-site/index.html public-site/multipage-index.html public-site/assets/css/site.css
git diff --cached --quiet && fail "No homepage accent changes were staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"
COMMIT_ID="$(git rev-parse --short HEAD)"

log ""
log "=== Publishing homepage service accents ==="
for file in index.html multipage-index.html; do
  aws_cmd s3 cp "$PUBLIC_SITE/$file" "s3://$BUCKET_NAME/$file" \
    --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate'
done
aws_cmd s3 cp "$SITE_CSS" "s3://$BUCKET_NAME/assets/css/site.css" \
  --content-type 'text/css; charset=utf-8' --cache-control 'public,max-age=300,must-revalidate'
LIVE_REPLACED=1
INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths '/' '/index.html' '/multipage-index.html' '/assets/css/site.css' \
  --query 'Invalidation.Id' --output text)"
log "CloudFront invalidation: $INVALIDATION_ID"
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

log ""
log "=== Verifying live homepage service accents ==="
for pair in "/:$WORK_DIR/root.html" "/index.html:$WORK_DIR/index.html" "/multipage-index.html:$WORK_DIR/multipage-index.html"; do
  path="${pair%%:*}"; output="${pair#*:}"
  code="$(curl -sS -L -o "$output" -w '%{http_code}' "https://proudpops.denduluru.com$path?v=$COMMIT_ID-$STAMP")"
  [[ "$code" == "200" ]] || fail "$path returned HTTP $code."
  grep -Fq -- 'PROUDPOPS-HOME-SERVICE-ACCENTS-V1' "$output" || fail "$path is missing the live accent marker."
  grep -Fq -- 'Five ways to get' "$output" || fail "$path lost the Services heading."
  log "PASS live homepage: $path"
done
CSS_CODE="$(curl -sS -L -o "$WORK_DIR/site.css" -w '%{http_code}' "https://proudpops.denduluru.com/assets/css/site.css?v=$COMMIT_ID-$STAMP")"
[[ "$CSS_CODE" == "200" ]] || fail "Live site.css returned HTTP $CSS_CODE."
grep -Fq -- 'PROUDPOPS-HOME-SERVICE-ACCENTS-V1' "$WORK_DIR/site.css" || fail "Live accent CSS marker is missing."
grep -Fq -- 'height: 5px' "$WORK_DIR/site.css" || fail "Live top-accent rule is missing."

for page in /book.html /services.html /about.html /gallery.html /contact.html; do
  code="$(curl -sS -L -o /dev/null -w '%{http_code}' "https://proudpops.denduluru.com$page?protected=$STAMP")"
  [[ "$code" == "200" ]] || fail "$page returned HTTP $code."
done

log ""
log "=== Pushing verified homepage accent commit ==="
if ! git push origin "$BRANCH"; then
  LIVE_REPLACED=0
  fail "Production verified but Git push failed. Retry: git push origin $BRANCH"
fi
LIVE_REPLACED=0
SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean after deployment."

log ""
log "SUCCESS: Transparent outlines and top accents added to homepage service cards."
log "Commit: $COMMIT_ID"
log "Backup: $BACKUP_DIR"
log "Homepage: https://proudpops.denduluru.com/"
