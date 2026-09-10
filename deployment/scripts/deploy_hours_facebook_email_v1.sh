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
COMMIT_MESSAGE="Add business hours Facebook and email"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/hours-social-email-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

FACEBOOK_URL="https://www.facebook.com/p/Proud-Pops-Barbershop-100063230739040/"
EMAIL="edgeuptight21@gmail.com"
EMAIL_HREF="mailto:edgeuptight21@gmail.com"
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
  aws_cmd s3 cp "$BACKUP_DIR/s3-before/site.css" \
    "s3://$BUCKET_NAME/assets/css/site.css" \
    --content-type 'text/css; charset=utf-8' \
    --cache-control 'public,max-age=300,must-revalidate' >/dev/null || true
  rollback_id="$(aws_cmd cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" \
    --paths '/' '/index.html' '/multipage-index.html' '/book.html' \
      '/services.html' '/about.html' '/gallery.html' '/contact.html' \
      '/assets/css/site.css' \
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

log "=== Proud Pops Hours, Facebook, and Email V1 ==="
log "Email: $EMAIL"
log "Facebook: $FACEBOOK_URL"
log "Hours: Tue-Wed 10 AM-6 PM, Thu-Fri 10 AM-8 PM, Sat 10 AM-5 PM"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$SITE_CSS" ]] || fail "site.css is missing."
[[ -f "$STATE_FILE" ]] || fail "AWS state file is missing."
for file in "${HTML_FILES[@]}"; do [[ -s "$PUBLIC_SITE/$file" ]] || fail "Missing public-site/$file"; done

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
START='<!-- PROUDPOPS-HOURS-SOCIAL-EMAIL-V1-START -->'; END='<!-- PROUDPOPS-HOURS-SOCIAL-EMAIL-V1-END -->'
CONTACT_START='<!-- PROUDPOPS-CONTACT-HOURS-SOCIAL-V1-START -->'; CONTACT_END='<!-- PROUDPOPS-CONTACT-HOURS-SOCIAL-V1-END -->'
facebook='https://www.facebook.com/p/Proud-Pops-Barbershop-100063230739040/'
email='edgeuptight21@gmail.com'

footer_block=f'''{START}
<div class="pp-footer-business-details">
  <div class="pp-footer-hours">
    <h3>Business Hours</h3>
    <dl>
      <div><dt>Monday</dt><dd>Closed</dd></div>
      <div><dt>Tuesday-Wednesday</dt><dd>10:00 AM-6:00 PM</dd></div>
      <div><dt>Thursday-Friday</dt><dd>10:00 AM-8:00 PM</dd></div>
      <div><dt>Saturday</dt><dd>10:00 AM-5:00 PM</dd></div>
      <div><dt>Sunday</dt><dd>Closed</dd></div>
    </dl>
  </div>
  <div class="pp-footer-connect">
    <h3>Connect</h3>
    <a href="mailto:{email}">{email}</a>
    <a href="{facebook}" target="_blank" rel="noopener noreferrer">Facebook</a>
  </div>
</div>
{END}'''

for path in pages:
    text=path.read_text(encoding='utf-8')
    pattern=re.compile(re.escape(START)+r'.*?'+re.escape(END),re.S)
    if pattern.search(text):
        text=pattern.sub(footer_block,text,count=1)
    else:
        location=re.search(r'<!-- PROUDPOPS-FOOTER-LOCATION-V1-END -->',text)
        if location:
            pos=location.end()
        else:
            footer_close=re.search(r'</footer\s*>',text,re.I)
            if not footer_close: raise SystemExit(f'ERROR: footer missing in {path.name}')
            pos=footer_close.start()
        text=text[:pos]+'\n'+footer_block+text[pos:]
    marker='<!-- PROUDPOPS-HOURS-FACEBOOK-EMAIL-V1 -->'
    if marker not in text:text=text.replace('</head>',f'  {marker}\n</head>',1)
    path.write_text('\n'.join(line.rstrip() for line in text.splitlines()).rstrip()+'\n',encoding='utf-8')

contact_path=root/'contact.html'; contact=contact_path.read_text(encoding='utf-8')
contact_block=f'''{CONTACT_START}
<section class="pp-contact-business-details" aria-labelledby="contact-business-details-title">
  <div class="pp-wrap pp-contact-business-grid">
    <article class="pp-card pp-contact-hours-card">
      <p class="pp-kicker">Plan your visit</p>
      <h2 id="contact-business-details-title">Business hours</h2>
      <dl>
        <div><dt>Monday</dt><dd>Closed</dd></div>
        <div><dt>Tuesday-Wednesday</dt><dd>10:00 AM-6:00 PM</dd></div>
        <div><dt>Thursday-Friday</dt><dd>10:00 AM-8:00 PM</dd></div>
        <div><dt>Saturday</dt><dd>10:00 AM-5:00 PM</dd></div>
        <div><dt>Sunday</dt><dd>Closed</dd></div>
      </dl>
    </article>
    <article class="pp-card pp-contact-connect-card">
      <p class="pp-kicker">Contact and social</p>
      <h2>Connect with Proud Pops.</h2>
      <a class="pp-contact-detail-link" href="mailto:{email}">{email}</a>
      <a class="pp-button pp-button-secondary" href="{facebook}" target="_blank" rel="noopener noreferrer">Visit Facebook Page</a>
    </article>
  </div>
</section>
{CONTACT_END}'''
pattern=re.compile(re.escape(CONTACT_START)+r'.*?'+re.escape(CONTACT_END),re.S)
if pattern.search(contact):
    contact=pattern.sub(contact_block,contact,count=1)
else:
    footer=re.search(r'<footer\b',contact,re.I)
    if not footer: raise SystemExit('ERROR: contact footer missing')
    contact=contact[:footer.start()]+contact_block+'\n'+contact[footer.start():]
contact_path.write_text('\n'.join(line.rstrip() for line in contact.splitlines()).rstrip()+'\n',encoding='utf-8')

css=css_path.read_text(encoding='utf-8')
css=re.sub(r'\n?/\* PROUDPOPS-HOURS-SOCIAL-EMAIL-V1 \*/.*?/\* PROUDPOPS-HOURS-SOCIAL-EMAIL-V1-END \*/\n?','\n',css,flags=re.S)
css+=r'''

/* PROUDPOPS-HOURS-SOCIAL-EMAIL-V1 */
.pp-footer-business-details {
  width: min(var(--pp-content), calc(100% - 40px));
  margin: 24px auto 0;
  padding: 22px 24px;
  display: grid;
  grid-template-columns: minmax(0,1.4fr) minmax(220px,.6fr);
  gap: 34px;
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 14px;
  background: rgba(23,29,36,.58);
}
.pp-footer-business-details h3 { margin: 0 0 12px; color: var(--pp-text); }
.pp-footer-hours dl { margin: 0; display: grid; grid-template-columns: repeat(2,minmax(0,1fr)); gap: 7px 24px; }
.pp-footer-hours dl div { display: flex; justify-content: space-between; gap: 14px; color: var(--pp-muted); }
.pp-footer-hours dt { font-weight: 800; }
.pp-footer-hours dd { margin: 0; text-align: right; }
.pp-footer-connect { display: grid; align-content: start; gap: 10px; }
.pp-footer-connect a,.pp-contact-detail-link { color: var(--pp-logo-blue,#49a9d7); font-weight: 850; overflow-wrap: anywhere; text-decoration: none; }
.pp-contact-business-details { padding: 0 0 72px; background: linear-gradient(145deg,#171c22,#232a32); }
.pp-contact-business-grid { display: grid; grid-template-columns: repeat(2,minmax(0,1fr)); gap: 22px; }
.pp-contact-hours-card,.pp-contact-connect-card { padding: 30px; }
.pp-contact-business-grid h2 { margin: 0 0 18px; font-size: clamp(30px,4vw,44px); line-height: 1; }
.pp-contact-hours-card dl { margin: 0; display: grid; gap: 9px; }
.pp-contact-hours-card dl div { display: flex; justify-content: space-between; gap: 20px; padding-bottom: 9px; border-bottom: 1px solid rgba(255,255,255,.09); }
.pp-contact-hours-card dt { color: var(--pp-text); font-weight: 850; }
.pp-contact-hours-card dd { margin: 0; color: var(--pp-muted); text-align: right; }
.pp-contact-connect-card { display: flex; flex-direction: column; align-items: flex-start; }
.pp-contact-connect-card .pp-button { margin-top: 20px; }
@media (max-width: 900px) {
  .pp-footer-business-details,.pp-contact-business-grid { grid-template-columns: 1fr; }
}
@media (max-width: 620px) {
  .pp-footer-business-details { padding: 20px; }
  .pp-footer-hours dl { grid-template-columns: 1fr; }
  .pp-contact-hours-card,.pp-contact-connect-card { padding: 22px; }
}
/* PROUDPOPS-HOURS-SOCIAL-EMAIL-V1-END */
'''
css_path.write_text('\n'.join(line.rstrip() for line in css.splitlines()).rstrip()+'\n',encoding='utf-8')
PY

for file in "${HTML_FILES[@]}"; do
  page="$PUBLIC_SITE/$file"
  for required in 'PROUDPOPS-HOURS-FACEBOOK-EMAIL-V1' 'Tuesday-Wednesday' '10:00 AM-6:00 PM' 'Thursday-Friday' '10:00 AM-8:00 PM' 'Saturday' '10:00 AM-5:00 PM' "$EMAIL" "$FACEBOOK_URL"; do grep -Fq -- "$required" "$page" || fail "$file missing $required"; done
done
for required in 'PROUDPOPS-CONTACT-HOURS-SOCIAL-V1' 'Business hours' 'Visit Facebook Page' "$EMAIL"; do grep -Fq -- "$required" "$PUBLIC_SITE/contact.html" || fail "contact.html missing $required"; done
for required in 'PROUDPOPS-HOURS-SOCIAL-EMAIL-V1' '.pp-footer-business-details' '.pp-contact-business-grid'; do grep -Fq -- "$required" "$SITE_CSS" || fail "site.css missing $required"; done
git diff --check || fail "Git whitespace validation failed."
git add -- public-site/index.html public-site/multipage-index.html public-site/book.html public-site/services.html public-site/about.html public-site/gallery.html public-site/contact.html public-site/assets/css/site.css
git diff --cached --quiet && fail "No changes staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"; COMMIT_ID="$(git rev-parse --short HEAD)"

for file in "${HTML_FILES[@]}"; do aws_cmd s3 cp "$PUBLIC_SITE/$file" "s3://$BUCKET_NAME/$file" --content-type 'text/html; charset=utf-8' --cache-control 'no-cache,no-store,must-revalidate'; done
aws_cmd s3 cp "$SITE_CSS" "s3://$BUCKET_NAME/assets/css/site.css" --content-type 'text/css; charset=utf-8' --cache-control 'public,max-age=300,must-revalidate'
LIVE_REPLACED=1
INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths '/' '/index.html' '/multipage-index.html' '/book.html' '/services.html' '/about.html' '/gallery.html' '/contact.html' '/assets/css/site.css' --query 'Invalidation.Id' --output text)"
log "CloudFront invalidation: $INVALIDATION_ID"
aws_cmd cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

verify(){ local path="$1" out="$2" code; code="$(curl -sS -L -o "$out" -w '%{http_code}' "https://proudpops.denduluru.com$path?v=$COMMIT_ID-$STAMP")"; [[ "$code" == 200 ]] || fail "$path returned $code"; for x in 'Tuesday-Wednesday' '10:00 AM-6:00 PM' 'Thursday-Friday' '10:00 AM-8:00 PM' 'Saturday' '10:00 AM-5:00 PM' "$EMAIL" "$FACEBOOK_URL"; do grep -Fq -- "$x" "$out" || fail "$path missing $x"; done; log "PASS: $path"; }
verify / "$WORK_DIR/root.html"
for file in "${HTML_FILES[@]}"; do verify "/$file" "$WORK_DIR/$file"; done
CSS_CODE="$(curl -sS -L -o "$WORK_DIR/site.css" -w '%{http_code}' "https://proudpops.denduluru.com/assets/css/site.css?v=$COMMIT_ID-$STAMP")"
[[ "$CSS_CODE" == 200 ]] || fail "CSS returned $CSS_CODE"
grep -Fq 'PROUDPOPS-HOURS-SOCIAL-EMAIL-V1' "$WORK_DIR/site.css" || fail "Live CSS marker missing"

if ! git push origin "$BRANCH"; then LIVE_REPLACED=0; fail "Production verified but Git push failed. Retry git push origin $BRANCH"; fi
LIVE_REPLACED=0; SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean."
log "SUCCESS: Business hours, Facebook, and email added across the site."
log "Commit: $COMMIT_ID"
log "Backup: $BACKUP_DIR"
