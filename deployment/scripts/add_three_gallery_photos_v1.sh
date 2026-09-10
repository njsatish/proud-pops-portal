#!/usr/bin/env bash
set -euo pipefail

EXPECTED_BRANCH="${EXPECTED_BRANCH:-proud-pops-v1}"
EXPECTED_AWS_ACCOUNT="${PROUDPOPS_AWS_ACCOUNT:-460425809139}"
AWS_PROFILE_NAME="${PROUDPOPS_AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
REPO="${1:-$HOME/Downloads/proud-pops-portal}"
PUBLIC_SITE="$REPO/public-site"
GALLERY_HTML="$PUBLIC_SITE/gallery.html"
GALLERY_CSS="$PUBLIC_SITE/assets/css/gallery.css"
GALLERY_DIR="$PUBLIC_SITE/assets/images/gallery"
STATE_FILE="$REPO/deployment/proud-pops-aws-state.env"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/add-three-gallery-photos-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

SOURCE_FILES=(
  "${PROUDPOPS_GALLERY_PHOTO_10:-$HOME/Downloads/proud_pops_10.webp}"
  "${PROUDPOPS_GALLERY_PHOTO_11:-$HOME/Downloads/proud_pops_11.webp}"
  "${PROUDPOPS_GALLERY_PHOTO_12:-$HOME/Downloads/proud_pops_12.jpeg}"
)
OUTPUT_NAMES=(
  "proud-pops-work-10.jpg"
  "proud-pops-work-11.jpg"
  "proud-pops-work-12.jpg"
)

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }

restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  log "Restoring previous live Gallery page..."
  aws_cmd s3 cp "$BACKUP_DIR/s3-gallery-before.html" "s3://$BUCKET_NAME/gallery.html" \
    --content-type 'text/html; charset=utf-8' \
    --cache-control 'no-cache,no-store,must-revalidate' >/dev/null || true
  for name in "${OUTPUT_NAMES[@]}"; do
    if [[ -s "$BACKUP_DIR/s3-before-$name" ]]; then
      aws_cmd s3 cp "$BACKUP_DIR/s3-before-$name" "s3://$BUCKET_NAME/assets/images/gallery/$name" \
        --content-type 'image/jpeg' --cache-control 'public,max-age=86400,must-revalidate' >/dev/null || true
    else
      aws_cmd s3 rm "s3://$BUCKET_NAME/assets/images/gallery/$name" >/dev/null 2>&1 || true
    fi
  done
  id="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
    --paths '/gallery.html' '/assets/images/gallery/proud-pops-work-10.jpg' \
      '/assets/images/gallery/proud-pops-work-11.jpg' \
      '/assets/images/gallery/proud-pops-work-12.jpg' \
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

log "=== Proud Pops Add Three Gallery Photos V1 ==="
log "Thumbnail treatment: uniform 4:5 crop"
log "Lightbox treatment: complete uncropped source"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$GALLERY_HTML" ]] || fail "Gallery page is missing: $GALLERY_HTML"
[[ -s "$GALLERY_CSS" ]] || fail "Gallery CSS is missing: $GALLERY_CSS"
[[ -f "$STATE_FILE" ]] || fail "AWS deployment state is missing: $STATE_FILE"
command -v sips >/dev/null 2>&1 || fail "macOS sips is required."

for source in "${SOURCE_FILES[@]}"; do
  [[ -s "$source" ]] || fail "Source photo is missing or empty: $source"
done

grep -Fq -- 'pp-gallery-grid' "$GALLERY_HTML" || fail "Gallery grid markup is missing."
grep -Fq -- 'aspect-ratio: 4 / 5' "$GALLERY_CSS" || fail "Uniform 4:5 Gallery CSS is not deployed yet."
grep -Fq -- 'object-fit: cover' "$GALLERY_CSS" || fail "Gallery thumbnail crop rule is missing."
grep -Fq -- 'object-fit: contain' "$GALLERY_CSS" || fail "Gallery lightbox contain rule is missing."

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

mkdir -p "$BACKUP_DIR" "$GALLERY_DIR"
chmod 700 "$BACKUP_DIR"
cp "$GALLERY_HTML" "$BACKUP_DIR/repository-gallery-before.html"
for name in "${OUTPUT_NAMES[@]}"; do
  [[ -s "$GALLERY_DIR/$name" ]] && cp "$GALLERY_DIR/$name" "$BACKUP_DIR/repository-before-$name"
done
aws_cmd s3 cp "s3://$BUCKET_NAME/gallery.html" "$BACKUP_DIR/s3-gallery-before.html" --only-show-errors
[[ -s "$BACKUP_DIR/s3-gallery-before.html" ]] || fail "Could not back up deployed Gallery page."
for name in "${OUTPUT_NAMES[@]}"; do
  aws_cmd s3 cp "s3://$BUCKET_NAME/assets/images/gallery/$name" "$BACKUP_DIR/s3-before-$name" --only-show-errors || true
done
chmod -R go-rwx "$BACKUP_DIR"

log ""
log "=== Optimizing the three source photos ==="
for index in 0 1 2; do
  source="${SOURCE_FILES[$index]}"
  output="$GALLERY_DIR/${OUTPUT_NAMES[$index]}"
  sips -s format jpeg -s formatOptions 88 -Z 1800 "$source" --out "$output" >/dev/null
  [[ -s "$output" ]] || fail "Could not create $output"
  width="$(sips -g pixelWidth "$output" | awk '/pixelWidth/{print $2}')"
  height="$(sips -g pixelHeight "$output" | awk '/pixelHeight/{print $2}')"
  [[ -n "$width" && -n "$height" ]] || fail "Could not inspect ${OUTPUT_NAMES[$index]}"
  [[ "$width" -ge 500 && "$height" -ge 500 ]] || fail "${OUTPUT_NAMES[$index]} is unexpectedly small: ${width}x${height}"
  log "PASS optimized: ${OUTPUT_NAMES[$index]} (${width}x${height})"
done

python3 - "$GALLERY_HTML" <<'PY'
from pathlib import Path
import re
import sys

path=Path(sys.argv[1]); text=path.read_text(encoding='utf-8')
START='<!-- PROUDPOPS-THREE-NEW-GALLERY-PHOTOS-V1-START -->'
END='<!-- PROUDPOPS-THREE-NEW-GALLERY-PHOTOS-V1-END -->'
items=[
 ('proud-pops-work-10.jpg','Proud Pops haircut and grooming portfolio image 10'),
 ('proud-pops-work-11.jpg','Proud Pops haircut and beard portfolio image 11'),
 ('proud-pops-work-12.jpg','Proud Pops haircut and beard portfolio image 12'),
]
block=START+'\n'+ '\n'.join(
 f'''          <button class="pp-gallery-item" type="button" data-gallery-item data-gallery-src="/assets/images/gallery/{name}" data-gallery-alt="{alt}" aria-label="Open portfolio image {i}">
            <img src="/assets/images/gallery/{name}" alt="{alt}" loading="lazy" decoding="async">
            <span class="pp-gallery-zoom" aria-hidden="true">View</span>
          </button>'''
 for i,(name,alt) in enumerate(items,start=10)
)+'\n'+END
pattern=re.compile(re.escape(START)+r'.*?'+re.escape(END),re.S)
if pattern.search(text):
    text=pattern.sub(block,text,count=1)
else:
    grid=re.search(r'<div\b[^>]*class=["\'][^"\']*pp-gallery-grid[^"\']*["\'][^>]*>',text,re.I)
    if not grid: raise SystemExit('ERROR: Gallery grid not found')
    tags=re.compile(r'<div\b[^>]*>|</div\s*>',re.I); depth=0; close=None
    for m in tags.finditer(text,grid.start()):
        if m.group(0).lower().startswith('</div'):
            depth-=1
            if depth==0: close=m.start(); break
        else: depth+=1
    if close is None: raise SystemExit('ERROR: Gallery grid is unbalanced')
    text=text[:close]+block+'\n        '+text[close:]
marker='<!-- PROUDPOPS-ADDED-GALLERY-PHOTOS-10-12-V1 -->'
if marker not in text:text=text.replace('</head>',f'  {marker}\n</head>',1)
path.write_text('\n'.join(x.rstrip() for x in text.splitlines()).rstrip()+'\n',encoding='utf-8')
PY

for name in "${OUTPUT_NAMES[@]}"; do
  grep -Fq -- "/assets/images/gallery/$name" "$GALLERY_HTML" || fail "Gallery HTML is missing $name"
done
[[ "$(grep -c 'PROUDPOPS-THREE-NEW-GALLERY-PHOTOS-V1-START' "$GALLERY_HTML")" -eq 1 ]] || fail "New-photo block marker count is incorrect."
[[ "$(grep -c 'proud-pops-work-1[012].jpg' "$GALLERY_HTML")" -eq 6 ]] || fail "Expected image and lightbox references for all three photos."
git diff --check || fail "Git whitespace validation failed."
git add -- public-site/gallery.html \
  public-site/assets/images/gallery/proud-pops-work-10.jpg \
  public-site/assets/images/gallery/proud-pops-work-11.jpg \
  public-site/assets/images/gallery/proud-pops-work-12.jpg
git diff --cached --quiet && fail "No Gallery additions were staged."
git diff --cached --check
git commit -m "Add three new Proud Pops Gallery photos"
COMMIT_ID="$(git rev-parse --short HEAD)"

for name in "${OUTPUT_NAMES[@]}"; do
  aws_cmd s3 cp "$GALLERY_DIR/$name" "s3://$BUCKET_NAME/assets/images/gallery/$name" \
    --content-type 'image/jpeg' --cache-control 'public,max-age=86400,must-revalidate'
done
aws_cmd s3 cp "$GALLERY_HTML" "s3://$BUCKET_NAME/gallery.html" \
  --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate'
LIVE_REPLACED=1

INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths '/gallery.html' '/assets/images/gallery/proud-pops-work-10.jpg' \
    '/assets/images/gallery/proud-pops-work-11.jpg' \
    '/assets/images/gallery/proud-pops-work-12.jpg' \
  --query 'Invalidation.Id' --output text)"
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

code="$(curl -sS -L -o "$WORK_DIR/gallery.html" -w '%{http_code}' "https://proudpops.denduluru.com/gallery.html?v=$COMMIT_ID-$STAMP")"
[[ "$code" == 200 ]] || fail "Live Gallery returned HTTP $code."
for name in "${OUTPUT_NAMES[@]}"; do
  grep -Fq -- "/assets/images/gallery/$name" "$WORK_DIR/gallery.html" || fail "Live Gallery is missing $name"
  img_code="$(curl -sS -L -o "$WORK_DIR/$name" -w '%{http_code}' "https://proudpops.denduluru.com/assets/images/gallery/$name?v=$COMMIT_ID")"
  [[ "$img_code" == 200 && -s "$WORK_DIR/$name" ]] || fail "Live image failed: $name"
  log "PASS live image: $name"
done

for page in /index.html /book.html /services.html /about.html /contact.html; do
  pcode="$(curl -sS -L -o /dev/null -w '%{http_code}' "https://proudpops.denduluru.com$page?protected=$STAMP")"
  [[ "$pcode" == 200 ]] || fail "$page returned HTTP $pcode."
done

if ! git push origin "$BRANCH"; then
  LIVE_REPLACED=0
  fail "Production verified but Git push failed. Retry: git push origin $BRANCH"
fi
LIVE_REPLACED=0
SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean after deployment."

log ""
log "SUCCESS: Three new photos added to the uniform Gallery grid."
log "Commit: $COMMIT_ID"
log "Gallery: https://proudpops.denduluru.com/gallery.html"
log "Backup: $BACKUP_DIR"
