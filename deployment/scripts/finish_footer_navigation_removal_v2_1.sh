#!/usr/bin/env bash
set -euo pipefail

EXPECTED_BRANCH="${EXPECTED_BRANCH:-proud-pops-v1}"
EXPECTED_AWS_ACCOUNT="${PROUDPOPS_AWS_ACCOUNT:-460425809139}"
AWS_PROFILE_NAME="${PROUDPOPS_AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
REPO="${1:-$HOME/Downloads/proud-pops-portal}"
PUBLIC_SITE="$REPO/public-site"
SITE_CSS="$PUBLIC_SITE/assets/css/site.css"
STATE_FILE="$REPO/deployment/proud-pops-aws-state.env"
COMMIT_MESSAGE="Finish removing repeated footer navigation columns"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/footer-navigation-removal-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0
HTML_FILES=(index.html multipage-index.html book.html services.html about.html gallery.html contact.html)

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }

restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  log "Restoring previous live pages and CSS..."
  for file in "${HTML_FILES[@]}"; do
    [[ -s "$BACKUP_DIR/s3-before/$file" ]] || continue
    aws_cmd s3 cp "$BACKUP_DIR/s3-before/$file" "s3://$BUCKET_NAME/$file" \
      --content-type 'text/html; charset=utf-8' \
      --cache-control 'no-cache,no-store,must-revalidate' >/dev/null || true
  done
  aws_cmd s3 cp "$BACKUP_DIR/s3-before/site.css" "s3://$BUCKET_NAME/assets/css/site.css" \
    --content-type 'text/css; charset=utf-8' \
    --cache-control 'public,max-age=300,must-revalidate' >/dev/null || true
  id="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
    --paths '/' '/index.html' '/multipage-index.html' '/book.html' '/services.html' \
      '/about.html' '/gallery.html' '/contact.html' '/assets/css/site.css' \
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

log "=== Finish Proud Pops Footer Navigation Removal V2.1 ==="
log "Removing footer columns: Explore and Visit"
log "Preserving: brand, address, phone, directions, hours, email, Facebook"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$SITE_CSS" ]] || fail "site.css is missing."
[[ -f "$STATE_FILE" ]] || fail "AWS state file is missing."
for file in "${HTML_FILES[@]}"; do [[ -s "$PUBLIC_SITE/$file" ]] || fail "Missing $file"; done

cd "$REPO"
BRANCH="$(git branch --show-current)"
[[ "$BRANCH" == "$EXPECTED_BRANCH" ]] || fail "Current branch is '$BRANCH'; expected '$EXPECTED_BRANCH'."
# Recovery mode accepts only the expected footer-related working-tree files
# left by the earlier footer attempt. Any unrelated change stops the script.
EXPECTED_PATHS=(
  public-site/index.html
  public-site/multipage-index.html
  public-site/book.html
  public-site/services.html
  public-site/about.html
  public-site/gallery.html
  public-site/contact.html
  public-site/assets/css/site.css
)
CHANGED_FILE="$WORK_DIR/changed-paths.txt"
git status --porcelain | sed -E 's/^.. //' | sort -u > "$CHANGED_FILE"
[[ -s "$CHANGED_FILE" ]] || fail "No pending footer changes were found. Use the standard V2 script instead."
while IFS= read -r changed; do
  [[ -n "$changed" ]] || continue
  allowed=0
  for expected in "${EXPECTED_PATHS[@]}"; do
    if [[ "$changed" == "$expected" ]]; then allowed=1; break; fi
  done
  [[ "$allowed" -eq 1 ]] || fail "Unexpected modified file: $changed"
  log "EXPECTED PENDING CHANGE: $changed"
done < "$CHANGED_FILE"

git fetch origin "$BRANCH"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$BRANCH")" ]] || fail "Local branch and origin/$BRANCH differ."

ACTUAL_ACCOUNT="$(aws_cmd sts get-caller-identity --query Account --output text)"
[[ "$ACTUAL_ACCOUNT" == "$EXPECTED_AWS_ACCOUNT" ]] || fail "Wrong AWS account: $ACTUAL_ACCOUNT"
BUCKET_NAME="$(read_state BUCKET_NAME)"
DISTRIBUTION_ID="$(read_state DISTRIBUTION_ID)"
[[ -n "$BUCKET_NAME" && -n "$DISTRIBUTION_ID" ]] || fail "AWS deployment state is incomplete."

mkdir -p "$BACKUP_DIR/repository-before" "$BACKUP_DIR/s3-before"
chmod 700 "$BACKUP_DIR"
for file in "${HTML_FILES[@]}"; do
  cp "$PUBLIC_SITE/$file" "$BACKUP_DIR/repository-before/$file"
  aws_cmd s3 cp "s3://$BUCKET_NAME/$file" "$BACKUP_DIR/s3-before/$file" --only-show-errors
  [[ -s "$BACKUP_DIR/s3-before/$file" ]] || fail "Could not back up $file"
done
cp "$SITE_CSS" "$BACKUP_DIR/repository-before/site.css"
aws_cmd s3 cp "s3://$BUCKET_NAME/assets/css/site.css" "$BACKUP_DIR/s3-before/site.css" --only-show-errors
[[ -s "$BACKUP_DIR/s3-before/site.css" ]] || fail "Could not back up site.css"
chmod -R go-rwx "$BACKUP_DIR"

python3 - "$PUBLIC_SITE" "$SITE_CSS" <<'PY'
from pathlib import Path
import re
import sys

root=Path(sys.argv[1]); css_path=Path(sys.argv[2])
pages=[root/name for name in ("index.html","multipage-index.html","book.html","services.html","about.html","gallery.html","contact.html")]
marker='<!-- PROUDPOPS-FOOTER-NAV-COLUMNS-REMOVED-V2 -->'

def matching_div(text, heading_start, footer_start):
    tags=list(re.finditer(r'<div\b[^>]*>|</div\s*>',text[footer_start:heading_start],re.I))
    stack=[]
    for m in tags:
        absolute=footer_start+m.start()
        if m.group(0).lower().startswith('</div'):
            if stack: stack.pop()
        else: stack.append(absolute)
    if not stack: raise SystemExit('ERROR: heading has no parent div')
    opening=stack[-1]
    tag_pattern=re.compile(r'<div\b[^>]*>|</div\s*>',re.I)
    depth=0
    for m in tag_pattern.finditer(text,opening):
        if m.group(0).lower().startswith('</div'):
            depth-=1
            if depth==0:return opening,m.end()
        else:depth+=1
    raise SystemExit('ERROR: unclosed footer column')

for path in pages:
    text=path.read_text(encoding='utf-8')
    footer_open=re.search(r'<footer\b[^>]*class=["\'][^"\']*pp-site-footer[^"\']*["\'][^>]*>',text,re.I)
    footer_close=re.search(r'</footer\s*>',text[footer_open.end():],re.I) if footer_open else None
    if not footer_open or not footer_close: raise SystemExit(f'ERROR: footer missing in {path.name}')
    footer_end=footer_open.end()+footer_close.end()
    removed=[]
    for heading in ('Explore','Visit'):
        search=text[footer_open.start():footer_end]
        hm=re.search(r'<h3\b[^>]*>\s*'+re.escape(heading)+r'\s*</h3>',search,re.I)
        if not hm:
            continue
        hs=footer_open.start()+hm.start()
        a,b=matching_div(text,hs,footer_open.start())
        text=text[:a]+'\n'+text[b:]
        removed.append(heading)
        footer_close=re.search(r'</footer\s*>',text[footer_open.end():],re.I)
        footer_end=footer_open.end()+footer_close.end()
    if not removed:
        print(f'INFO footer navigation already absent: {path.name}')
    footer_html=text[footer_open.start():footer_end]
    for forbidden in ('>Explore<','>Visit<'):
        if forbidden.lower() in re.sub(r'\s+','',footer_html).lower():
            raise SystemExit(f'ERROR: {path.name} still contains {forbidden}')
    for required in ('pp-footer-logo-lockup','pp-footer-location','1118 Main Street Southwest','(540) 819-1346','Business Hours','edgeuptight21@gmail.com','Facebook'):
        if required not in footer_html: raise SystemExit(f'ERROR: {path.name} lost {required}')
    if marker not in text:text=text.replace('</head>',f'  {marker}\n</head>',1)
    path.write_text('\n'.join(x.rstrip() for x in text.splitlines()).rstrip()+'\n',encoding='utf-8')
    print(f'PASS footer cleanup: {path.name}; removed={removed}')

css=css_path.read_text(encoding='utf-8')
css=re.sub(r'\n?/\* PROUDPOPS-FOOTER-NAV-COLUMNS-REMOVED-V2 \*/.*?/\* PROUDPOPS-FOOTER-NAV-COLUMNS-REMOVED-V2-END \*/\n?','\n',css,flags=re.S)
css+=r'''

/* PROUDPOPS-FOOTER-NAV-COLUMNS-REMOVED-V2 */
.pp-footer-grid {
  display: block;
  padding-bottom: 4px;
}
.pp-footer-grid > div:first-child {
  max-width: 680px;
}
.pp-footer-grid > div:first-child p {
  max-width: 620px;
  margin: 0;
  line-height: 1.65;
}
.pp-footer-location { margin-top: 24px; }
.pp-footer-business-details { margin-top: 18px; }
/* PROUDPOPS-FOOTER-NAV-COLUMNS-REMOVED-V2-END */
'''
css_path.write_text('\n'.join(x.rstrip() for x in css.splitlines()).rstrip()+'\n',encoding='utf-8')
PY

log ""
log "=== Validating local footers ==="
for file in "${HTML_FILES[@]}"; do
  page="$PUBLIC_SITE/$file"
  grep -Fq 'PROUDPOPS-FOOTER-NAV-COLUMNS-REMOVED-V2' "$page" || fail "$file missing marker"
  footer="$WORK_DIR/$file.footer"
  python3 - "$page" "$footer" <<'PY'
from pathlib import Path
import re,sys
text=Path(sys.argv[1]).read_text(); m=re.search(r'<footer\b.*?</footer\s*>',text,re.S|re.I)
if not m: raise SystemExit('footer missing')
Path(sys.argv[2]).write_text(m.group(0))
PY
  if grep -Eqi '<h3[^>]*>[[:space:]]*(Explore|Visit)[[:space:]]*</h3>' "$footer"; then fail "$file still contains Explore or Visit column"; fi
  for required in '1118 Main Street Southwest' '(540) 819-1346' 'Business Hours' 'edgeuptight21@gmail.com' 'Facebook'; do grep -Fq "$required" "$footer" || fail "$file lost $required"; done
  log "PASS local footer: $file"
done
grep -Fq 'PROUDPOPS-FOOTER-NAV-COLUMNS-REMOVED-V2' "$SITE_CSS" || fail "CSS marker missing"
git diff --check || fail "Git whitespace validation failed."
git add -- public-site/index.html public-site/multipage-index.html public-site/book.html public-site/services.html public-site/about.html public-site/gallery.html public-site/contact.html public-site/assets/css/site.css
git diff --cached --quiet && fail "No footer changes staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"; COMMIT_ID="$(git rev-parse --short HEAD)"

for file in "${HTML_FILES[@]}"; do aws_cmd s3 cp "$PUBLIC_SITE/$file" "s3://$BUCKET_NAME/$file" --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate'; done
aws_cmd s3 cp "$SITE_CSS" "s3://$BUCKET_NAME/assets/css/site.css" --content-type 'text/css; charset=utf-8' --cache-control 'public,max-age=300,must-revalidate'
LIVE_REPLACED=1
INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths '/' '/index.html' '/multipage-index.html' '/book.html' '/services.html' '/about.html' '/gallery.html' '/contact.html' '/assets/css/site.css' --query 'Invalidation.Id' --output text)"
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

verify(){ local path="$1" out="$2" code; code="$(curl -sS -L -o "$out" -w '%{http_code}' "https://proudpops.denduluru.com$path?v=$COMMIT_ID-$STAMP")"; [[ "$code" == 200 ]] || fail "$path returned $code"; footer="$out.footer"; python3 - "$out" "$footer" <<'PY'
from pathlib import Path
import re,sys
text=Path(sys.argv[1]).read_text();m=re.search(r'<footer\b.*?</footer\s*>',text,re.S|re.I)
if not m:raise SystemExit('footer missing')
Path(sys.argv[2]).write_text(m.group(0))
PY
if grep -Eqi '<h3[^>]*>[[:space:]]*(Explore|Visit)[[:space:]]*</h3>' "$footer"; then fail "$path still contains footer navigation"; fi; for x in '1118 Main Street Southwest' '(540) 819-1346' 'Business Hours' 'edgeuptight21@gmail.com' 'Facebook'; do grep -Fq "$x" "$footer" || fail "$path lost $x"; done; log "PASS live: $path"; }
verify / "$WORK_DIR/root.html"
for file in "${HTML_FILES[@]}"; do verify "/$file" "$WORK_DIR/$file"; done

if ! git push origin "$BRANCH"; then LIVE_REPLACED=0; fail "Production verified but Git push failed. Retry git push origin $BRANCH"; fi
LIVE_REPLACED=0; SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean."
log "SUCCESS: Explore and Visit footer columns removed across the site."
log "Commit: $COMMIT_ID"
log "Backup: $BACKUP_DIR"
