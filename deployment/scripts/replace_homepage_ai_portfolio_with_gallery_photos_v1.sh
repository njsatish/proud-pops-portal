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
GALLERY_DIR="$PUBLIC_SITE/assets/images/gallery"
STATE_FILE="$REPO/deployment/proud-pops-aws-state.env"
COMMIT_MESSAGE="Replace homepage portfolio images with real Gallery photos"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/homepage-real-gallery-photos-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

IMAGE_NAMES=(
  proud-pops-work-10.jpg
  proud-pops-work-11.jpg
  proud-pops-work-12.jpg
)
IMAGE_URLS=(
  /assets/images/gallery/proud-pops-work-10.jpg
  /assets/images/gallery/proud-pops-work-11.jpg
  /assets/images/gallery/proud-pops-work-12.jpg
)

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }

restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  log "Restoring previous live homepages..."
  for file in index.html multipage-index.html; do
    aws_cmd s3 cp "$BACKUP_DIR/s3-$file" "s3://$BUCKET_NAME/$file" \
      --content-type 'text/html; charset=utf-8' \
      --cache-control 'no-cache,no-store,must-revalidate' >/dev/null || true
  done
  id="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
    --paths '/' '/index.html' '/multipage-index.html' \
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

log "=== Proud Pops Replace Homepage Portfolio With Gallery Photos V1 ==="
log "Large image: proud-pops-work-10.jpg"
log "Small images: proud-pops-work-11.jpg and proud-pops-work-12.jpg"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$INDEX" ]] || fail "Homepage is missing: $INDEX"
[[ -s "$STAGED_HOME" ]] || fail "Staged homepage is missing: $STAGED_HOME"
[[ -f "$STATE_FILE" ]] || fail "AWS deployment state is missing: $STATE_FILE"
for name in "${IMAGE_NAMES[@]}"; do
  [[ -s "$GALLERY_DIR/$name" ]] || fail "Gallery image is missing: $GALLERY_DIR/$name"
done
for page in "$INDEX" "$STAGED_HOME"; do
  grep -Fq -- 'Detail you can see.' "$page" || fail "Portfolio heading is missing from $(basename "$page")."
  grep -Fq -- 'View Full Gallery' "$page" || fail "View Full Gallery link is missing from $(basename "$page")."
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
aws_cmd s3 cp "s3://$BUCKET_NAME/index.html" "$BACKUP_DIR/s3-index.html" --only-show-errors
aws_cmd s3 cp "s3://$BUCKET_NAME/multipage-index.html" "$BACKUP_DIR/s3-multipage-index.html" --only-show-errors
[[ -s "$BACKUP_DIR/s3-index.html" && -s "$BACKUP_DIR/s3-multipage-index.html" ]] || fail "Could not back up live homepages."
chmod 600 "$BACKUP_DIR"/*

python3 - "$INDEX" "$STAGED_HOME" <<'PY'
from pathlib import Path
import re
import sys

paths=[Path(sys.argv[1]),Path(sys.argv[2])]
urls=[
 '/assets/images/gallery/proud-pops-work-10.jpg',
 '/assets/images/gallery/proud-pops-work-11.jpg',
 '/assets/images/gallery/proud-pops-work-12.jpg',
]
alts=[
 'Proud Pops portfolio haircut detail from the real Gallery, image 10',
 'Proud Pops portfolio haircut detail from the real Gallery, image 11',
 'Proud Pops portfolio haircut detail from the real Gallery, image 12',
]
marker='<!-- PROUDPOPS-HOMEPAGE-REAL-GALLERY-PHOTOS-V1 -->'
section_tags=re.compile(r'<section\b[^>]*>|</section\s*>',re.I)

def section_spans(text):
    stack=[]; spans=[]
    for match in section_tags.finditer(text):
        if match.group(0).lower().startswith('</section'):
            if not stack: raise SystemExit('ERROR: unmatched closing section')
            spans.append((stack.pop(),match.end()))
        else:
            stack.append(match.start())
    if stack: raise SystemExit('ERROR: unclosed section')
    return sorted(spans,key=lambda pair:(pair[1]-pair[0],pair[0]))

for path in paths:
    text=path.read_text(encoding='utf-8')
    candidates=[]
    for start,end in section_spans(text):
        block=text[start:end]
        if 'Detail you can see.' in block and 'View Full Gallery' in block:
            candidates.append((end-start,start,end))
    if len(candidates)!=1:
        raise SystemExit(f'ERROR: expected one Portfolio section in {path.name}; found {len(candidates)}')
    _,start,end=candidates[0]
    block=text[start:end]
    images=list(re.finditer(r'<img\b[^>]*>',block,re.I))
    if len(images)<3:
        raise SystemExit(f'ERROR: expected at least three Portfolio images in {path.name}; found {len(images)}')
    replacements=[]
    for index,img in enumerate(images[:3]):
        tag=img.group(0)
        tag=re.sub(r'\s+src=["\'][^"\']*["\']','',tag,flags=re.I)
        tag=re.sub(r'\s+alt=["\'][^"\']*["\']','',tag,flags=re.I)
        tag=tag[:-1]+f' src="{urls[index]}" alt="{alts[index]}" loading="lazy" decoding="async">'
        replacements.append((img.start(),img.end(),tag))
    for a,b,replacement in reversed(replacements):
        block=block[:a]+replacement+block[b:]
    text=text[:start]+block+text[end:]
    if marker not in text:
        text=text.replace('</head>',f'  {marker}\n</head>',1)
    path.write_text('\n'.join(line.rstrip() for line in text.splitlines()).rstrip()+'\n',encoding='utf-8')
    print(f'PASS replaced first three Portfolio images: {path.name}')
PY

log ""
log "=== Validating homepage Portfolio replacement ==="
for page in "$INDEX" "$STAGED_HOME"; do
  grep -Fq -- 'PROUDPOPS-HOMEPAGE-REAL-GALLERY-PHOTOS-V1' "$page" || fail "Marker missing from $(basename "$page")."
  for url in "${IMAGE_URLS[@]}"; do
    grep -Fq -- "$url" "$page" || fail "$(basename "$page") is missing $url"
  done
  grep -Fq -- 'View Full Gallery' "$page" || fail "$(basename "$page") lost View Full Gallery."
  log "PASS local homepage: $(basename "$page")"
done

git diff --check || fail "Git whitespace validation failed."
git add -- public-site/index.html public-site/multipage-index.html
git diff --cached --quiet && fail "No homepage photo replacements were staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"
COMMIT_ID="$(git rev-parse --short HEAD)"

log ""
log "=== Publishing real Gallery photos on homepage ==="
for file in index.html multipage-index.html; do
  aws_cmd s3 cp "$PUBLIC_SITE/$file" "s3://$BUCKET_NAME/$file" \
    --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate'
done
LIVE_REPLACED=1
INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths '/' '/index.html' '/multipage-index.html' \
    '/assets/images/gallery/proud-pops-work-10.jpg' \
    '/assets/images/gallery/proud-pops-work-11.jpg' \
    '/assets/images/gallery/proud-pops-work-12.jpg' \
  --query 'Invalidation.Id' --output text)"
log "CloudFront invalidation: $INVALIDATION_ID"
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

log ""
log "=== Verifying live homepage Portfolio ==="
for pair in "/:$WORK_DIR/root.html" "/index.html:$WORK_DIR/index.html" "/multipage-index.html:$WORK_DIR/staged.html"; do
  path="${pair%%:*}"; output="${pair#*:}"
  code="$(curl -sS -L -o "$output" -w '%{http_code}' "https://proudpops.denduluru.com$path?v=$COMMIT_ID-$STAMP")"
  [[ "$code" == "200" ]] || fail "$path returned HTTP $code."
  for url in "${IMAGE_URLS[@]}"; do grep -Fq -- "$url" "$output" || fail "$path is missing $url"; done
  grep -Fq -- 'View Full Gallery' "$output" || fail "$path lost View Full Gallery."
  log "PASS live homepage: $path"
done
for name in "${IMAGE_NAMES[@]}"; do
  code="$(curl -sS -L -o "$WORK_DIR/$name" -w '%{http_code}' "https://proudpops.denduluru.com/assets/images/gallery/$name?v=$COMMIT_ID")"
  [[ "$code" == "200" && -s "$WORK_DIR/$name" ]] || fail "Live Gallery image failed: $name"
  log "PASS live image: $name"
done

if ! git push origin "$BRANCH"; then
  LIVE_REPLACED=0
  fail "Production verified but Git push failed. Retry: git push origin $BRANCH"
fi
LIVE_REPLACED=0
SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean after deployment."

log ""
log "SUCCESS: Homepage synthetic Portfolio images replaced with three real Gallery photos."
log "Commit: $COMMIT_ID"
log "Images: proud-pops-work-10.jpg, proud-pops-work-11.jpg, proud-pops-work-12.jpg"
log "Backup: $BACKUP_DIR"
log "Homepage: https://proudpops.denduluru.com/"
