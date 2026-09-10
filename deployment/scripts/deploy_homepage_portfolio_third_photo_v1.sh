#!/usr/bin/env bash
set -euo pipefail

EXPECTED_BRANCH="${EXPECTED_BRANCH:-proud-pops-v1}"
EXPECTED_AWS_ACCOUNT="${PROUDPOPS_AWS_ACCOUNT:-460425809139}"
AWS_PROFILE_NAME="${PROUDPOPS_AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
REPO="${1:-$HOME/Downloads/proud-pops-portal}"
SOURCE_PHOTO="${2:-${PROUDPOPS_HOME_PORTFOLIO_PHOTO_3:-$HOME/Downloads/proud_pops_homepage_portfolio_3.jpg}}"
PUBLIC_SITE="$REPO/public-site"
INDEX="$PUBLIC_SITE/index.html"
STAGED_HOME="$PUBLIC_SITE/multipage-index.html"
IMAGE_DIR="$PUBLIC_SITE/assets/images/home"
OUTPUT_NAME="proud-pops-portfolio-real-3.jpg"
OUTPUT_FILE="$IMAGE_DIR/$OUTPUT_NAME"
OUTPUT_URL="/assets/images/home/$OUTPUT_NAME"
STATE_FILE="$REPO/deployment/proud-pops-aws-state.env"
COMMIT_MESSAGE="Replace third homepage portfolio image with real work"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/home-portfolio-third-photo-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }

restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  log "Restoring previous live homepages and third image..."
  for file in index.html multipage-index.html; do
    [[ -s "$BACKUP_DIR/s3-$file" ]] || continue
    aws_cmd s3 cp "$BACKUP_DIR/s3-$file" "s3://$BUCKET_NAME/$file" \
      --content-type 'text/html; charset=utf-8' \
      --cache-control 'no-cache,no-store,must-revalidate' >/dev/null || true
  done
  if [[ -s "$BACKUP_DIR/s3-image-before.jpg" ]]; then
    aws_cmd s3 cp "$BACKUP_DIR/s3-image-before.jpg" "s3://$BUCKET_NAME/assets/images/home/$OUTPUT_NAME" \
      --content-type 'image/jpeg' --cache-control 'public,max-age=86400,must-revalidate' >/dev/null || true
  else
    aws_cmd s3 rm "s3://$BUCKET_NAME/assets/images/home/$OUTPUT_NAME" >/dev/null 2>&1 || true
  fi
  id="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
    --paths '/' '/index.html' '/multipage-index.html' "$OUTPUT_URL" \
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

log "=== Proud Pops Homepage Third Portfolio Photo V1 ==="
log "Repository: $REPO"
log "Source photo: $SOURCE_PHOTO"
log "Homepage asset: $OUTPUT_URL"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$SOURCE_PHOTO" ]] || fail "Source photo is missing or empty: $SOURCE_PHOTO"
[[ -s "$INDEX" ]] || fail "Homepage is missing: $INDEX"
[[ -s "$STAGED_HOME" ]] || fail "Staged homepage is missing: $STAGED_HOME"
[[ -f "$STATE_FILE" ]] || fail "AWS deployment state is missing: $STATE_FILE"
command -v sips >/dev/null 2>&1 || fail "macOS sips is required."

for page in "$INDEX" "$STAGED_HOME"; do
  grep -Fq -- 'Detail you can see.' "$page" || fail "Portfolio section is missing from $(basename "$page")."
  grep -Fq -- 'View Full Gallery' "$page" || fail "Gallery link is missing from $(basename "$page")."
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

mkdir -p "$BACKUP_DIR" "$IMAGE_DIR"
chmod 700 "$BACKUP_DIR"
cp "$INDEX" "$BACKUP_DIR/repository-index.html"
cp "$STAGED_HOME" "$BACKUP_DIR/repository-multipage-index.html"
[[ -s "$OUTPUT_FILE" ]] && cp "$OUTPUT_FILE" "$BACKUP_DIR/repository-image-before.jpg"
aws_cmd s3 cp "s3://$BUCKET_NAME/index.html" "$BACKUP_DIR/s3-index.html" --only-show-errors
aws_cmd s3 cp "s3://$BUCKET_NAME/multipage-index.html" "$BACKUP_DIR/s3-multipage-index.html" --only-show-errors
aws_cmd s3 cp "s3://$BUCKET_NAME/assets/images/home/$OUTPUT_NAME" "$BACKUP_DIR/s3-image-before.jpg" --only-show-errors || true
[[ -s "$BACKUP_DIR/s3-index.html" && -s "$BACKUP_DIR/s3-multipage-index.html" ]] || fail "Could not back up live homepages."
chmod -R go-rwx "$BACKUP_DIR"

log ""
log "=== Optimizing the new third photo ==="
sips -s format jpeg -s formatOptions 90 -Z 1800 "$SOURCE_PHOTO" --out "$OUTPUT_FILE" >/dev/null
[[ -s "$OUTPUT_FILE" ]] || fail "Could not create optimized image: $OUTPUT_FILE"
WIDTH="$(sips -g pixelWidth "$OUTPUT_FILE" | awk '/pixelWidth/{print $2}')"
HEIGHT="$(sips -g pixelHeight "$OUTPUT_FILE" | awk '/pixelHeight/{print $2}')"
[[ -n "$WIDTH" && -n "$HEIGHT" ]] || fail "Could not inspect optimized image dimensions."
[[ "$WIDTH" -ge 700 && "$HEIGHT" -ge 700 ]] || fail "Optimized image is unexpectedly small: ${WIDTH}x${HEIGHT}"
log "PASS optimized image: ${WIDTH}x${HEIGHT}"

python3 - "$INDEX" "$STAGED_HOME" "$OUTPUT_URL" <<'PY'
from pathlib import Path
import re
import sys

paths=[Path(sys.argv[1]),Path(sys.argv[2])]
url=sys.argv[3]
marker='<!-- PROUDPOPS-HOMEPAGE-PORTFOLIO-THIRD-REAL-V1 -->'
section_tag=re.compile(r'<section\b[^>]*>|</section\s*>',re.I)

def spans(text):
    stack=[]; out=[]
    for m in section_tag.finditer(text):
        if m.group(0).lower().startswith('</section'):
            if not stack: raise SystemExit('ERROR: unmatched section close')
            out.append((stack.pop(),m.end()))
        else: stack.append(m.start())
    if stack: raise SystemExit('ERROR: unclosed section')
    return sorted(out,key=lambda x:(x[1]-x[0],x[0]))

for path in paths:
    text=path.read_text(encoding='utf-8')
    matches=[]
    for a,b in spans(text):
        block=text[a:b]
        if 'Detail you can see.' in block and 'View Full Gallery' in block:
            matches.append((b-a,a,b))
    if len(matches)!=1:
        raise SystemExit(f'ERROR: expected one Portfolio section in {path.name}; found {len(matches)}')
    _,a,b=matches[0]
    block=text[a:b]
    images=list(re.finditer(r'<img\b[^>]*>',block,re.I))
    if len(images)<3:
        raise SystemExit(f'ERROR: expected three Portfolio images in {path.name}; found {len(images)}')
    image=images[2]
    tag=image.group(0)
    tag=re.sub(r'\s+src=["\'][^"\']*["\']','',tag,flags=re.I)
    tag=re.sub(r'\s+alt=["\'][^"\']*["\']','',tag,flags=re.I)
    tag=re.sub(r'\s+loading=["\'][^"\']*["\']','',tag,flags=re.I)
    tag=re.sub(r'\s+decoding=["\'][^"\']*["\']','',tag,flags=re.I)
    tag=tag[:-1]+f' src="{url}" alt="Proud Pops close-profile beard shaping and grooming detail" loading="lazy" decoding="async">'
    block=block[:image.start()]+tag+block[image.end():]
    text=text[:a]+block+text[b:]
    if marker not in text:
        text=text.replace('</head>',f'  {marker}\n</head>',1)
    path.write_text('\n'.join(x.rstrip() for x in text.splitlines()).rstrip()+'\n',encoding='utf-8')
    print(f'PASS replaced third Portfolio image: {path.name}')
PY

log ""
log "=== Validating local homepage replacement ==="
for page in "$INDEX" "$STAGED_HOME"; do
  grep -Fq -- 'PROUDPOPS-HOMEPAGE-PORTFOLIO-THIRD-REAL-V1' "$page" || fail "Marker missing from $(basename "$page")."
  grep -Fq -- "$OUTPUT_URL" "$page" || fail "New third image is missing from $(basename "$page")."
  grep -Fq -- 'View Full Gallery' "$page" || fail "Gallery link was lost from $(basename "$page")."
  log "PASS local homepage: $(basename "$page")"
done

git diff --check || fail "Git whitespace validation failed."
git add -- public-site/index.html public-site/multipage-index.html "public-site/assets/images/home/$OUTPUT_NAME"
git diff --cached --quiet && fail "No third-photo changes were staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"
COMMIT_ID="$(git rev-parse --short HEAD)"

log ""
log "=== Publishing new third portfolio photo ==="
aws_cmd s3 cp "$OUTPUT_FILE" "s3://$BUCKET_NAME/assets/images/home/$OUTPUT_NAME" \
  --content-type 'image/jpeg' --cache-control 'public,max-age=86400,must-revalidate'
for file in index.html multipage-index.html; do
  aws_cmd s3 cp "$PUBLIC_SITE/$file" "s3://$BUCKET_NAME/$file" \
    --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate'
done
LIVE_REPLACED=1
INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths '/' '/index.html' '/multipage-index.html' "$OUTPUT_URL" \
  --query 'Invalidation.Id' --output text)"
log "CloudFront invalidation: $INVALIDATION_ID"
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

log ""
log "=== Verifying live homepage and image ==="
for pair in "/:$WORK_DIR/root.html" "/index.html:$WORK_DIR/index.html" "/multipage-index.html:$WORK_DIR/staged.html"; do
  path="${pair%%:*}"; output="${pair#*:}"
  code="$(curl -sS -L -o "$output" -w '%{http_code}' "https://proudpops.denduluru.com$path?v=$COMMIT_ID-$STAMP")"
  [[ "$code" == "200" ]] || fail "$path returned HTTP $code."
  grep -Fq -- "$OUTPUT_URL" "$output" || fail "$path is missing the new third image."
  grep -Fq -- 'View Full Gallery' "$output" || fail "$path lost View Full Gallery."
  log "PASS live homepage: $path"
done
IMAGE_CODE="$(curl -sS -L -o "$WORK_DIR/$OUTPUT_NAME" -w '%{http_code}' "https://proudpops.denduluru.com$OUTPUT_URL?v=$COMMIT_ID")"
[[ "$IMAGE_CODE" == "200" && -s "$WORK_DIR/$OUTPUT_NAME" ]] || fail "New live image failed verification."
log "PASS live image: $OUTPUT_URL"

for page in /book.html /services.html /about.html /gallery.html /contact.html; do
  code="$(curl -sS -L -o /dev/null -w '%{http_code}' "https://proudpops.denduluru.com$page?protected=$STAMP")"
  [[ "$code" == "200" ]] || fail "$page returned HTTP $code."
done

log ""
log "=== Pushing verified third-photo commit ==="
if ! git push origin "$BRANCH"; then
  LIVE_REPLACED=0
  fail "Production verified but Git push failed. Retry: git push origin $BRANCH"
fi
LIVE_REPLACED=0
SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean after deployment."

log ""
log "SUCCESS: New close-profile photo deployed as the third homepage Portfolio image."
log "Commit: $COMMIT_ID"
log "Image: $OUTPUT_URL"
log "Backup: $BACKUP_DIR"
log "Homepage: https://proudpops.denduluru.com/"
