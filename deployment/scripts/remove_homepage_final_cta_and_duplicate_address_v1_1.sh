#!/usr/bin/env bash
set -euo pipefail
EXPECTED_BRANCH="${EXPECTED_BRANCH:-proud-pops-v1}"
EXPECTED_AWS_ACCOUNT="${PROUDPOPS_AWS_ACCOUNT:-460425809139}"
AWS_PROFILE_NAME="${PROUDPOPS_AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
REPO="${1:-$HOME/Downloads/proud-pops-portal}"
PUBLIC_SITE="$REPO/public-site"
STATE_FILE="$REPO/deployment/proud-pops-aws-state.env"
COMMIT_MESSAGE="Remove redundant homepage CTA and duplicate address"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/homepage-footer-cleanup-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0
HOME_FILES=(index.html multipage-index.html)
log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }
restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  for file in "${HOME_FILES[@]}"; do
    [[ -s "$BACKUP_DIR/s3-before/$file" ]] || continue
    aws_cmd s3 cp "$BACKUP_DIR/s3-before/$file" "s3://$BUCKET_NAME/$file" --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate' >/dev/null || true
  done
  id="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths '/' '/index.html' '/multipage-index.html' --query 'Invalidation.Id' --output text 2>/dev/null || true)"
  [[ -z "$id" || "$id" == "None" ]] || aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$id" 2>/dev/null || true
}
cleanup(){ local code=$?; trap - EXIT INT TERM; if [[ "$SUCCESS" -ne 1 && "$code" -ne 0 ]]; then restore_live; fi; rm -rf "$WORK_DIR"; exit "$code"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

log "=== Proud Pops Homepage Footer Cleanup V1.1 ==="
log "Remove: Ready to choose a time frame"
log "Remove: duplicate homepage address line when present"
log "Preserve: complete footer address card"
[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -f "$STATE_FILE" ]] || fail "AWS state file is missing."
for file in "${HOME_FILES[@]}"; do [[ -s "$PUBLIC_SITE/$file" ]] || fail "Missing public-site/$file"; done
cd "$REPO"
BRANCH="$(git branch --show-current)"
[[ "$BRANCH" == "$EXPECTED_BRANCH" ]] || fail "Current branch is '$BRANCH'; expected '$EXPECTED_BRANCH'."
[[ -z "$(git status --porcelain)" ]] || { git status --short; fail "Repository has uncommitted changes."; }
git fetch origin "$BRANCH"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$BRANCH")" ]] || fail "Local branch and origin/$BRANCH differ."
ACTUAL_ACCOUNT="$(aws_cmd sts get-caller-identity --query Account --output text)"
[[ "$ACTUAL_ACCOUNT" == "$EXPECTED_AWS_ACCOUNT" ]] || fail "Wrong AWS account: $ACTUAL_ACCOUNT"
BUCKET_NAME="$(read_state BUCKET_NAME)"; DISTRIBUTION_ID="$(read_state DISTRIBUTION_ID)"
[[ -n "$BUCKET_NAME" && -n "$DISTRIBUTION_ID" ]] || fail "AWS deployment state is incomplete."
mkdir -p "$BACKUP_DIR/repository-before" "$BACKUP_DIR/s3-before"; chmod 700 "$BACKUP_DIR"
for file in "${HOME_FILES[@]}"; do cp "$PUBLIC_SITE/$file" "$BACKUP_DIR/repository-before/$file"; aws_cmd s3 cp "s3://$BUCKET_NAME/$file" "$BACKUP_DIR/s3-before/$file" --only-show-errors; done
chmod -R go-rwx "$BACKUP_DIR"

python3 - "$PUBLIC_SITE/index.html" "$PUBLIC_SITE/multipage-index.html" <<'PY'
from pathlib import Path
import re, sys
paths=[Path(x) for x in sys.argv[1:]]
cleanup='<!-- PROUDPOPS-HOMEPAGE-FOOTER-CLEANUP-V1 -->'
start='<!-- PROUDPOPS-HOME-LOCATION-V1-START -->'; end='<!-- PROUDPOPS-HOME-LOCATION-V1-END -->'
section_tag=re.compile(r'<section\b[^>]*>|</section\s*>',re.I)
def spans(text):
    stack=[]; out=[]
    for m in section_tag.finditer(text):
        if m.group(0).lower().startswith('</section'):
            if not stack: raise SystemExit('ERROR: unmatched section close')
            out.append((stack.pop(),m.end()))
        else: stack.append(m.start())
    if stack: raise SystemExit('ERROR: unclosed section')
    return sorted(out,key=lambda v:(v[1]-v[0],v[0]))
def remove_div(text, cls):
    op=re.search(r'<div\b[^>]*class=["\'][^"\']*\b'+re.escape(cls)+r'\b[^"\']*["\'][^>]*>',text,re.I)
    if not op:return text,0
    tags=re.compile(r'<div\b[^>]*>|</div\s*>',re.I); depth=0
    for m in tags.finditer(text,op.start()):
        if m.group(0).lower().startswith('</div'):
            depth-=1
            if depth==0:return text[:op.start()]+'\n'+text[m.end():],1
        else: depth+=1
    raise SystemExit('ERROR: unclosed duplicate address div')
for path in paths:
    text=path.read_text(encoding='utf-8')
    candidates=[]
    for a,b in spans(text):
        block=text[a:b].lower()
        if 'pp-home-cta' in block and ('ready to choose a time?' in block or 'ready to choose an appointment?' in block): candidates.append((b-a,a,b))
    if len(candidates)!=1: raise SystemExit(f'ERROR: expected one final CTA in {path.name}, found {len(candidates)}')
    _,a,b=candidates[0]; text=text[:a]+'\n'+text[b:]
    marker=re.compile(r'\s*'+re.escape(start)+r'.*?'+re.escape(end)+r'\s*',re.S)
    text,mc=marker.subn('\n',text,count=1)
    text,dc=remove_div(text,'pp-home-location-line')
    text=text.replace(start,'').replace(end,'')
    for required in ('class="pp-footer-location"','1118 Main Street Southwest','(540) 819-1346','Get Directions'):
        if required not in text: raise SystemExit(f'ERROR: missing footer content {required} in {path.name}')
    if cleanup not in text:text=text.replace('</head>',f'  {cleanup}\n</head>',1)
    path.write_text('\n'.join(x.rstrip() for x in text.splitlines()).rstrip()+'\n',encoding='utf-8')
    print(f'PASS cleanup {path.name}: address removals={mc+dc}')
PY

for file in "${HOME_FILES[@]}"; do
  page="$PUBLIC_SITE/$file"
  grep -Fq 'PROUDPOPS-HOMEPAGE-FOOTER-CLEANUP-V1' "$page" || fail "$file missing cleanup marker"
  for forbidden in 'Ready to choose a time?' 'Ready to choose an appointment?' 'pp-home-location-line' 'PROUDPOPS-HOME-LOCATION-V1-START'; do grep -Fq "$forbidden" "$page" && fail "$file still contains $forbidden" || true; done
  for required in 'class="pp-footer-location"' '1118 Main Street Southwest' '(540) 819-1346' 'Get Directions'; do grep -Fq "$required" "$page" || fail "$file missing $required"; done
done
git diff --check || fail "Git whitespace validation failed."
git add -- public-site/index.html public-site/multipage-index.html
git diff --cached --quiet && fail "No cleanup changes staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"; COMMIT_ID="$(git rev-parse --short HEAD)"
for file in "${HOME_FILES[@]}"; do aws_cmd s3 cp "$PUBLIC_SITE/$file" "s3://$BUCKET_NAME/$file" --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate'; done
LIVE_REPLACED=1
INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths '/' '/index.html' '/multipage-index.html' --query 'Invalidation.Id' --output text)"
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"
verify(){ local path="$1" out="$2" code; code="$(curl -sS -L -o "$out" -w '%{http_code}' "https://proudpops.denduluru.com$path?v=$COMMIT_ID-$STAMP")"; [[ "$code" == 200 ]] || fail "$path returned $code"; for bad in 'Ready to choose a time?' 'Ready to choose an appointment?' 'pp-home-location-line'; do grep -Fq "$bad" "$out" && fail "$path still contains $bad" || true; done; grep -Fq 'class="pp-footer-location"' "$out" || fail "$path lost footer location"; log "PASS live: $path"; }
verify / "$WORK_DIR/root.html"; verify /index.html "$WORK_DIR/index.html"; verify /multipage-index.html "$WORK_DIR/staged.html"
for p in /book.html /services.html /about.html /gallery.html /contact.html; do code="$(curl -sS -L -o /dev/null -w '%{http_code}' "https://proudpops.denduluru.com$p?protected=$STAMP")"; [[ "$code" == 200 ]] || fail "$p returned $code"; done
if ! git push origin "$BRANCH"; then LIVE_REPLACED=0; fail "Production verified but Git push failed. Retry git push origin $BRANCH"; fi
LIVE_REPLACED=0; SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean."
log "SUCCESS: Redundant homepage CTA and duplicate address line removed."
log "Commit: $COMMIT_ID"
log "Footer address card preserved."
log "Backup: $BACKUP_DIR"
