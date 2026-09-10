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
COMMIT_MESSAGE="Apply guided service selector design"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/guided-service-selector-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

if [[ -s "$SERVICES_CSS" ]]; then
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
  log "Restoring previous live Services page and stylesheet..."
  aws_cmd s3 cp "$BACKUP_DIR/s3-services-before.html" "s3://$BUCKET_NAME/services.html" \
    --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate' >/dev/null || true
  aws_cmd s3 cp "$BACKUP_DIR/s3-css-before.css" "s3://$BUCKET_NAME/$CSS_S3_KEY" \
    --content-type 'text/css; charset=utf-8' --cache-control 'public,max-age=300,must-revalidate' >/dev/null || true
  id="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
    --paths '/services.html' "$CSS_URL_PATH" --query 'Invalidation.Id' --output text 2>/dev/null || true)"
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

log "=== Proud Pops Guided Service Selector V1 ==="
log "Stylesheet selected: $CSS_FILE"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$SERVICES_HTML" ]] || fail "Services page is missing: $SERVICES_HTML"
[[ -s "$CSS_FILE" ]] || fail "No usable stylesheet found."
[[ -f "$STATE_FILE" ]] || fail "AWS deployment state is missing: $STATE_FILE"

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
cp "$SERVICES_HTML" "$BACKUP_DIR/repository-services-before.html"
cp "$CSS_FILE" "$BACKUP_DIR/repository-css-before.css"
aws_cmd s3 cp "s3://$BUCKET_NAME/services.html" "$BACKUP_DIR/s3-services-before.html" --only-show-errors
aws_cmd s3 cp "s3://$BUCKET_NAME/$CSS_S3_KEY" "$BACKUP_DIR/s3-css-before.css" --only-show-errors
[[ -s "$BACKUP_DIR/s3-services-before.html" && -s "$BACKUP_DIR/s3-css-before.css" ]] || fail "Could not back up live Services assets."
chmod 600 "$BACKUP_DIR"/*

python3 - "$SERVICES_HTML" "$CSS_FILE" <<'PY'
from pathlib import Path
import re, sys

html_path, css_path = Path(sys.argv[1]), Path(sys.argv[2])
text, css = html_path.read_text(), css_path.read_text()
START='<!-- PROUDPOPS-GUIDED-SERVICE-SELECTOR-V1-START -->'
END='<!-- PROUDPOPS-GUIDED-SERVICE-SELECTOR-V1-END -->'
SCRIPT_START='<!-- PROUDPOPS-GUIDED-SERVICE-SCRIPT-V1-START -->'
SCRIPT_END='<!-- PROUDPOPS-GUIDED-SERVICE-SCRIPT-V1-END -->'
services=[
('haircut','Haircut','Haircut','$40','45 minutes','Complete shaping and finish','A complete haircut appointment designed around clean structure, precise edges, and a polished finish.'),
('beard-trim','Beard Trim','Beard Trim','$20','25 minutes','Beard shaping and clean edges','Shape and refine facial hair with clean edges, balanced detail, and a polished outline.'),
('shave','Shave','Shave','$15','20 minutes','A smooth refreshed finish','A clean, focused shave appointment for a smooth and refreshed finish.'),
('haircut-with-enhancement','Haircut With Enhancement','Enhancement','$50','60 minutes','Additional definition and detail','A full haircut appointment with additional enhancement detail for sharper definition.'),
('edgeup','Edgeup','Edgeup','$25','30 minutes','Hairline and perimeter refresh','Refresh the hairline and perimeter with crisp definition between full haircut appointments.')]
buttons=[]; panels=[]
for i,(sid,name,short,price,duration,focus,desc) in enumerate(services):
    active=i==0
    buttons.append(f'<button class="pp-service-choice{" is-active" if active else ""}" type="button" role="tab" id="service-tab-{sid}" aria-selected="{str(active).lower()}" aria-controls="service-panel-{sid}" tabindex="{0 if active else -1}" data-service-tab="{sid}"><span>{short}</span><small>{price} · {duration}</small></button>')
    hidden='' if active else ' hidden'
    panels.append(f'<article class="pp-service-detail{" is-active" if active else ""}" role="tabpanel" id="service-panel-{sid}" aria-labelledby="service-tab-{sid}" data-service-panel="{sid}"{hidden}><div class="pp-service-detail-head"><div><p class="pp-kicker">Selected service</p><h2>{name}</h2><p>{desc}</p></div><strong class="pp-service-detail-price">{price}</strong></div><div class="pp-service-detail-facts"><div><strong>{duration}</strong><span>Appointment length</span></div><div><strong>Consultation</strong><span>Confirm the desired result</span></div><div><strong>{focus}</strong><span>Service focus</span></div></div><div class="pp-service-detail-actions"><a class="pp-button pp-button-primary" href="/book.html?service={sid}">View {short} Times</a><a class="pp-button pp-button-secondary" href="/gallery.html">View Portfolio</a></div></article>')
block=START+'\n<div class="pp-guided-services" data-guided-services><div class="pp-service-choice-wrap"><div class="pp-service-choice-heading"><p class="pp-kicker">Choose a service</p><h2>What would you like to book?</h2></div><div class="pp-service-choice-list" role="tablist" aria-label="Proud Pops services">'+''.join(buttons)+'</div></div><div class="pp-service-detail-wrap">'+''.join(panels)+'</div></div>\n'+END
replaced=False
for a,b in [(START,END),('<!-- PROUDPOPS-SERVICE-SPOTLIGHT-V1-START -->','<!-- PROUDPOPS-SERVICE-SPOTLIGHT-V1-END -->')]:
    pat=re.compile(re.escape(a)+r'.*?'+re.escape(b),re.S)
    if pat.search(text): text=pat.sub(block,text,count=1); replaced=True; break
if not replaced:
    op=re.search(r'<div\b[^>]*class=["\'][^"\']*(?:pp-services-grid|pp-service-grid)[^"\']*["\'][^>]*>',text,re.I)
    if not op: raise SystemExit('ERROR: Current Services layout not found')
    tags=re.compile(r'<div\b[^>]*>|</div\s*>',re.I); depth=0; finish=None
    for m in tags.finditer(text,op.start()):
        if m.group(0).lower().startswith('</div'):
            depth-=1
            if depth==0: finish=m.end(); break
        else: depth+=1
    if finish is None: raise SystemExit('ERROR: Current Services layout is unbalanced')
    text=text[:op.start()]+block+text[finish:]
script=SCRIPT_START+'''\n<script>
(()=>{const root=document.querySelector('[data-guided-services]');if(!root)return;const tabs=[...root.querySelectorAll('[data-service-tab]')],panels=[...root.querySelectorAll('[data-service-panel]')];function activate(id,focus=false){tabs.forEach(t=>{const on=t.dataset.serviceTab===id;t.classList.toggle('is-active',on);t.setAttribute('aria-selected',String(on));t.tabIndex=on?0:-1;if(on&&focus)t.focus()});panels.forEach(p=>{const on=p.dataset.servicePanel===id;p.classList.toggle('is-active',on);p.hidden=!on})}tabs.forEach((t,i)=>{t.addEventListener('click',()=>activate(t.dataset.serviceTab));t.addEventListener('keydown',e=>{let n=null;if(e.key==='ArrowRight'||e.key==='ArrowDown')n=(i+1)%tabs.length;if(e.key==='ArrowLeft'||e.key==='ArrowUp')n=(i-1+tabs.length)%tabs.length;if(e.key==='Home')n=0;if(e.key==='End')n=tabs.length-1;if(n===null)return;e.preventDefault();activate(tabs[n].dataset.serviceTab,true)})});const q=new URLSearchParams(location.search).get('service'),aliases={'enhancement':'haircut-with-enhancement','haircut-enhancement':'haircut-with-enhancement'},id=aliases[q]||q;if(id&&tabs.some(t=>t.dataset.serviceTab===id))activate(id)})();
</script>\n'''+SCRIPT_END
pat=re.compile(re.escape(SCRIPT_START)+r'.*?'+re.escape(SCRIPT_END),re.S)
text=pat.sub(script,text,count=1) if pat.search(text) else text.replace('</body>',script+'\n</body>',1)
marker='<!-- PROUDPOPS-GUIDED-SERVICE-SELECTOR-DEPLOYED-V1 -->'
if marker not in text:text=text.replace('</head>',f'  {marker}\n</head>',1)
html_path.write_text('\n'.join(x.rstrip() for x in text.splitlines()).rstrip()+'\n')
css=re.sub(r'\n?/\* PROUDPOPS-GUIDED-SERVICE-SELECTOR-V1 \*/.*?/\* PROUDPOPS-GUIDED-SERVICE-SELECTOR-V1-END \*/\n?','\n',css,flags=re.S)
css+=r'''

/* PROUDPOPS-GUIDED-SERVICE-SELECTOR-V1 */
.pp-guided-services{display:grid;grid-template-columns:minmax(230px,.68fr) minmax(0,1.32fr);gap:22px;align-items:start}.pp-service-choice-wrap,.pp-service-detail{border:1px solid rgba(255,255,255,.12);border-radius:18px;background:#10171d;box-shadow:var(--pp-shadow)}.pp-service-choice-wrap{position:sticky;top:104px;padding:20px}.pp-service-choice-heading h2{margin:4px 0 18px;font-size:25px;line-height:1.05}.pp-service-choice-list{display:grid;gap:7px}.pp-service-choice{width:100%;padding:14px 15px;display:grid;gap:3px;border:1px solid transparent;border-radius:11px;background:transparent;color:var(--pp-muted);font:inherit;text-align:left;cursor:pointer}.pp-service-choice span{font-weight:900}.pp-service-choice small{opacity:.82}.pp-service-choice:hover,.pp-service-choice:focus-visible{border-color:rgba(73,169,215,.28);background:rgba(73,169,215,.08);color:var(--pp-text)}.pp-service-choice.is-active{border-color:rgba(73,169,215,.45);background:rgba(73,169,215,.15);color:var(--pp-text);box-shadow:inset 4px 0 0 var(--pp-logo-blue,#49a9d7)}.pp-service-detail-wrap{min-width:0}.pp-service-detail{min-height:520px;padding:34px}.pp-service-detail[hidden]{display:none!important}.pp-service-detail-head{display:flex;align-items:flex-start;justify-content:space-between;gap:28px}.pp-service-detail-head h2{margin:4px 0 12px;font-size:clamp(40px,6vw,68px);line-height:.94;letter-spacing:-.05em}.pp-service-detail-head p:not(.pp-kicker){max-width:680px;margin:0;color:var(--pp-muted);font-size:18px}.pp-service-detail-price{flex:0 0 auto;color:var(--pp-gold);font-size:clamp(48px,7vw,74px);line-height:.9}.pp-service-detail-facts{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin:38px 0 30px}.pp-service-detail-facts div{min-height:116px;padding:17px;display:flex;flex-direction:column;justify-content:space-between;border:1px solid rgba(255,255,255,.1);border-radius:13px;background:rgba(255,255,255,.025)}.pp-service-detail-facts strong{line-height:1.25}.pp-service-detail-facts span{color:var(--pp-muted);font-size:13px}.pp-service-detail-actions{display:flex;flex-wrap:wrap;gap:10px}
@media(max-width:900px){.pp-guided-services{grid-template-columns:1fr}.pp-service-choice-wrap{position:static;padding:16px}.pp-service-choice-heading{display:none}.pp-service-choice-list{display:flex;gap:8px;overflow-x:auto;padding-bottom:3px}.pp-service-choice{width:auto;min-width:max-content;padding:11px 14px}.pp-service-choice.is-active{box-shadow:inset 0 -3px 0 var(--pp-logo-blue,#49a9d7)}.pp-service-detail{min-height:0}}
@media(max-width:620px){.pp-service-detail{padding:23px;border-radius:15px}.pp-service-detail-head{flex-direction:column;gap:22px}.pp-service-detail-head h2{font-size:45px}.pp-service-detail-head p:not(.pp-kicker){font-size:16px}.pp-service-detail-price{font-size:56px}.pp-service-detail-facts{grid-template-columns:1fr;margin:28px 0 24px}.pp-service-detail-facts div{min-height:88px}.pp-service-detail-actions{display:grid}.pp-service-detail-actions .pp-button{width:100%;min-height:54px}}
/* PROUDPOPS-GUIDED-SERVICE-SELECTOR-V1-END */
'''
css_path.write_text('\n'.join(x.rstrip() for x in css.splitlines()).rstrip()+'\n')
PY

for id in haircut beard-trim shave haircut-with-enhancement edgeup; do
  grep -Fq -- "data-service-tab=\"$id\"" "$SERVICES_HTML" || fail "Missing service tab: $id"
  grep -Fq -- "/book.html?service=$id" "$SERVICES_HTML" || fail "Missing booking link: $id"
done
[[ "$(grep -c 'data-service-tab=' "$SERVICES_HTML")" -eq 5 ]] || fail "Expected five service tabs."
[[ "$(grep -c 'data-service-panel=' "$SERVICES_HTML")" -eq 5 ]] || fail "Expected five service panels."
grep -Fq -- 'PROUDPOPS-GUIDED-SERVICE-SELECTOR-V1' "$CSS_FILE" || fail "Guided Selector CSS marker is missing."
git diff --check || fail "Git whitespace validation failed."
git add -- public-site/services.html "$CSS_GIT_PATH"
git diff --cached --quiet && fail "No Guided Selector changes were staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"
COMMIT_ID="$(git rev-parse --short HEAD)"

aws_cmd s3 cp "$SERVICES_HTML" "s3://$BUCKET_NAME/services.html" --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate'
aws_cmd s3 cp "$CSS_FILE" "s3://$BUCKET_NAME/$CSS_S3_KEY" --content-type 'text/css; charset=utf-8' --cache-control 'public,max-age=300,must-revalidate'
LIVE_REPLACED=1
INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths '/services.html' "$CSS_URL_PATH" --query 'Invalidation.Id' --output text)"
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

HTML_CODE="$(curl -sS -L -o "$WORK_DIR/services.html" -w '%{http_code}' "https://proudpops.denduluru.com/services.html?v=$COMMIT_ID-$STAMP")"
CSS_CODE="$(curl -sS -L -o "$WORK_DIR/services.css" -w '%{http_code}' "https://proudpops.denduluru.com$CSS_URL_PATH?v=$COMMIT_ID-$STAMP")"
[[ "$HTML_CODE" == 200 && "$CSS_CODE" == 200 ]] || fail "Live Services assets did not return HTTP 200."
grep -Fq -- 'PROUDPOPS-GUIDED-SERVICE-SELECTOR-DEPLOYED-V1' "$WORK_DIR/services.html" || fail "Live selector marker is missing."
grep -Fq -- 'PROUDPOPS-GUIDED-SERVICE-SELECTOR-V1' "$WORK_DIR/services.css" || fail "Live selector CSS is missing."
for page in /index.html /book.html /about.html /gallery.html /contact.html; do
  code="$(curl -sS -L -o /dev/null -w '%{http_code}' "https://proudpops.denduluru.com$page?protected=$STAMP")"
  [[ "$code" == 200 ]] || fail "$page returned HTTP $code."
done

if ! git push origin "$BRANCH"; then
  LIVE_REPLACED=0
  fail "Production verified but Git push failed. Retry: git push origin $BRANCH"
fi
LIVE_REPLACED=0
SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean after deployment."

log "SUCCESS: Guided Service Selector deployed."
log "Commit: $COMMIT_ID"
log "Stylesheet: $CSS_URL_PATH"
log "Backup: $BACKUP_DIR"
