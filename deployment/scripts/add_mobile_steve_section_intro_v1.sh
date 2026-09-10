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
COMMIT_MESSAGE="Add mobile introduction before Steve section"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/mobile-steve-intro-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }

restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  log "Restoring previous live homepages and CSS..."
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

log "=== Proud Pops Mobile Steve Section Introduction V1 ==="
log "Mobile copy: Meet Steve / Experience behind every detail."
log "Desktop layout: unchanged"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$INDEX" && -s "$STAGED_HOME" && -s "$SITE_CSS" ]] || fail "Required homepage files are missing."
[[ -f "$STATE_FILE" ]] || fail "AWS deployment state is missing."
for page in "$INDEX" "$STAGED_HOME"; do
  grep -Fqi -- 'Steve' "$page" || fail "Steve content is missing from $(basename "$page")."
  grep -Fq -- 'Detail you can see.' "$page" || fail "Portfolio section is missing from $(basename "$page")."
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
for file in "$BACKUP_DIR/s3-index.html" "$BACKUP_DIR/s3-multipage-index.html" "$BACKUP_DIR/s3-site.css"; do
  [[ -s "$file" ]] || fail "Live backup failed: $file"
done
chmod 600 "$BACKUP_DIR"/*

python3 - "$INDEX" "$STAGED_HOME" "$SITE_CSS" <<'PY'
from pathlib import Path
import re
import sys

home_paths=[Path(sys.argv[1]),Path(sys.argv[2])]
css_path=Path(sys.argv[3])
START='<!-- PROUDPOPS-MOBILE-STEVE-INTRO-V1-START -->'
END='<!-- PROUDPOPS-MOBILE-STEVE-INTRO-V1-END -->'
intro=f'''{START}
<div class="pp-mobile-steve-intro" aria-labelledby="pp-mobile-steve-title">
  <p class="pp-mobile-steve-kicker">Meet Steve</p>
  <h2 id="pp-mobile-steve-title">Experience behind every detail.</h2>
  <p>See the person behind the chair and the focused approach that shapes every Proud Pops service.</p>
</div>
{END}'''
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

for path in home_paths:
    text=path.read_text(encoding='utf-8')
    pattern=re.compile(r'\s*'+re.escape(START)+r'.*?'+re.escape(END)+r'\s*',re.S)
    text=pattern.sub('\n',text)
    sections=spans(text)
    portfolio=None
    for _,a,b in [(b-a,a,b) for a,b in sections]:
        block=text[a:b]
        if 'Detail you can see.' in block:
            portfolio=(a,b)
            break
    if portfolio is None: raise SystemExit(f'ERROR: Portfolio section missing in {path.name}')
    next_sections=[(a,b) for a,b in sections if a>=portfolio[1]]
    steve=None
    for a,b in next_sections:
        block=text[a:b]
        if re.search(r'\bSteve\b',block,re.I):
            steve=(a,b)
            break
    if steve is None: raise SystemExit(f'ERROR: Steve section missing after Portfolio in {path.name}')
    a,b=steve
    block=text[a:b]
    first_content=re.search(r'<(?:div|article)\b',block,re.I)
    if first_content:
        pos=a+first_content.start()
    else:
        open_end=text.find('>',a,b)
        if open_end<0: raise SystemExit(f'ERROR: Steve section opening tag invalid in {path.name}')
        pos=open_end+1
    text=text[:pos]+'\n'+intro+'\n'+text[pos:]
    marker='<!-- PROUDPOPS-MOBILE-STEVE-INTRO-DEPLOYED-V1 -->'
    if marker not in text:text=text.replace('</head>',f'  {marker}\n</head>',1)
    path.write_text('\n'.join(line.rstrip() for line in text.splitlines()).rstrip()+'\n',encoding='utf-8')
    print(f'PASS inserted mobile Steve intro: {path.name}')

css=css_path.read_text(encoding='utf-8')
css=re.sub(r'\n?/\* PROUDPOPS-MOBILE-STEVE-INTRO-V1 \*/.*?/\* PROUDPOPS-MOBILE-STEVE-INTRO-V1-END \*/\n?','\n',css,flags=re.S)
css+=r'''

/* PROUDPOPS-MOBILE-STEVE-INTRO-V1 */
.pp-mobile-steve-intro { display: none; }
@media (max-width: 760px) {
  .pp-mobile-steve-intro {
    width: min(100% - 36px, 680px);
    margin: 0 auto 24px;
    padding: 0;
    display: block;
  }
  .pp-mobile-steve-kicker {
    margin: 0 0 8px;
    color: var(--pp-logo-blue,#49a9d7);
    font-size: 12px;
    font-weight: 950;
    letter-spacing: .18em;
    text-transform: uppercase;
  }
  .pp-mobile-steve-intro h2 {
    margin: 0;
    max-width: 620px;
    color: var(--pp-text,#f7f8fa);
    font-size: clamp(34px,10vw,48px);
    line-height: .98;
    letter-spacing: -.045em;
  }
  .pp-mobile-steve-intro > p:last-child {
    margin: 15px 0 0;
    max-width: 620px;
    color: var(--pp-muted,#aab5c1);
    font-size: 16px;
    line-height: 1.55;
  }
}
/* PROUDPOPS-MOBILE-STEVE-INTRO-V1-END */
'''
css_path.write_text('\n'.join(x.rstrip() for x in css.splitlines()).rstrip()+'\n',encoding='utf-8')
PY

log ""
log "=== Validating mobile Steve introduction ==="
for page in "$INDEX" "$STAGED_HOME"; do
  grep -Fq -- 'PROUDPOPS-MOBILE-STEVE-INTRO-DEPLOYED-V1' "$page" || fail "Marker missing from $(basename "$page")."
  grep -Fq -- 'class="pp-mobile-steve-intro"' "$page" || fail "Mobile intro missing from $(basename "$page")."
  grep -Fq -- 'Experience behind every detail.' "$page" || fail "Mobile heading missing from $(basename "$page")."
  grep -Fq -- 'See the person behind the chair' "$page" || fail "Mobile description missing from $(basename "$page")."
done
for required in 'PROUDPOPS-MOBILE-STEVE-INTRO-V1' '.pp-mobile-steve-intro { display: none; }' '@media (max-width: 760px)' 'display: block'; do
  grep -Fq -- "$required" "$SITE_CSS" || fail "CSS validation missing: $required"
done

git diff --check || fail "Git whitespace validation failed."
git add -- public-site/index.html public-site/multipage-index.html public-site/assets/css/site.css
git diff --cached --quiet && fail "No mobile Steve introduction changes were staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"
COMMIT_ID="$(git rev-parse --short HEAD)"

log ""
log "=== Publishing mobile Steve introduction ==="
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
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

log ""
log "=== Verifying live mobile introduction assets ==="
for pair in "/:$WORK_DIR/root.html" "/index.html:$WORK_DIR/index.html" "/multipage-index.html:$WORK_DIR/staged.html"; do
  path="${pair%%:*}"; output="${pair#*:}"
  code="$(curl -sS -L -o "$output" -w '%{http_code}' "https://proudpops.denduluru.com$path?v=$COMMIT_ID-$STAMP")"
  [[ "$code" == 200 ]] || fail "$path returned HTTP $code."
  grep -Fq -- 'pp-mobile-steve-intro' "$output" || fail "$path is missing the mobile Steve intro."
  grep -Fq -- 'Experience behind every detail.' "$output" || fail "$path is missing the mobile Steve heading."
  log "PASS live homepage: $path"
done
CSS_CODE="$(curl -sS -L -o "$WORK_DIR/site.css" -w '%{http_code}' "https://proudpops.denduluru.com/assets/css/site.css?v=$COMMIT_ID-$STAMP")"
[[ "$CSS_CODE" == 200 ]] || fail "Live CSS returned HTTP $CSS_CODE."
grep -Fq -- 'PROUDPOPS-MOBILE-STEVE-INTRO-V1' "$WORK_DIR/site.css" || fail "Live mobile intro CSS marker is missing."

if ! git push origin "$BRANCH"; then
  LIVE_REPLACED=0
  fail "Production verified but Git push failed. Retry: git push origin $BRANCH"
fi
LIVE_REPLACED=0
SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean after deployment."

log ""
log "SUCCESS: Mobile introduction added before the Steve photo."
log "Commit: $COMMIT_ID"
log "Desktop layout remains unchanged."
log "Backup: $BACKUP_DIR"
