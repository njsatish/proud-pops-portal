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
COMMIT_MESSAGE="Fix homepage service card accent targeting"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/home-service-accent-targeting-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }

restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  log "Restoring previous live homepage files..."
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

log "=== Fix Homepage Service Accent Targeting V1 ==="
log "Cause: previous CSS selectors did not match the actual service-card classes"
log "Fix: identify the five cards from their service names and Book actions"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$INDEX" && -s "$STAGED_HOME" && -s "$SITE_CSS" ]] || fail "Required homepage files are missing."
[[ -f "$STATE_FILE" ]] || fail "AWS deployment state is missing."

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
  [[ -s "$file" ]] || fail "Backup failed: $file"
done
chmod 600 "$BACKUP_DIR"/*

python3 - "$INDEX" "$STAGED_HOME" "$SITE_CSS" <<'PY'
from pathlib import Path
import re
import sys

home_paths = [Path(sys.argv[1]), Path(sys.argv[2])]
css_path = Path(sys.argv[3])
SCRIPT_START = '<!-- PROUDPOPS-ACTUAL-HOME-SERVICE-ACCENTS-V1-START -->'
SCRIPT_END = '<!-- PROUDPOPS-ACTUAL-HOME-SERVICE-ACCENTS-V1-END -->'

script = f'''{SCRIPT_START}
<script>
(() => {{
  const normalize = value => (value || '').replace(/\\s+/g, ' ').trim().toLowerCase();
  const expected = [
    ['haircut', 'pp-accent-haircut'],
    ['beard trim', 'pp-accent-beard'],
    ['shave', 'pp-accent-shave'],
    ['haircut with enhancement', 'pp-accent-enhancement'],
    ['edgeup', 'pp-accent-edgeup']
  ];

  const heading = [...document.querySelectorAll('h1,h2')]
    .find(node => normalize(node.textContent).includes('five ways to get'));
  const section = heading ? heading.closest('section') : null;
  if (!section) return;

  const candidates = [...section.querySelectorAll('article, li, div')]
    .filter(node => {{
      const text = normalize(node.textContent);
      const directBookLinks = [...node.querySelectorAll('a,button')]
        .filter(action => normalize(action.textContent) === 'book');
      return directBookLinks.length === 1 && expected.some(([name]) => text.includes(name));
    }})
    .sort((a, b) => a.querySelectorAll('*').length - b.querySelectorAll('*').length);

  const used = new Set();
  expected.forEach(([name, className], index) => {{
    const card = candidates.find(node => !used.has(node) && normalize(node.textContent).includes(name));
    if (!card) return;
    used.add(card);
    card.classList.add('pp-actual-home-service-card', className);
    card.dataset.serviceAccentIndex = String(index + 1);
  }});

  section.dataset.serviceAccentCards = String(used.size);
}})();
</script>
{SCRIPT_END}'''

for path in home_paths:
    text = path.read_text(encoding='utf-8')
    pattern = re.compile(re.escape(SCRIPT_START) + r'.*?' + re.escape(SCRIPT_END), re.S)
    if pattern.search(text):
        text = pattern.sub(script, text, count=1)
    else:
        text = text.replace('</body>', script + '\n</body>', 1)
    marker = '<!-- PROUDPOPS-ACTUAL-HOME-SERVICE-ACCENTS-DEPLOYED-V1 -->'
    if marker not in text:
        text = text.replace('</head>', f'  {marker}\n</head>', 1)
    path.write_text('\n'.join(line.rstrip() for line in text.splitlines()).rstrip() + '\n', encoding='utf-8')

css = css_path.read_text(encoding='utf-8')
css = re.sub(
    r'\n?/\* PROUDPOPS-ACTUAL-HOME-SERVICE-ACCENTS-V1 \*/.*?'
    r'/\* PROUDPOPS-ACTUAL-HOME-SERVICE-ACCENTS-V1-END \*/\n?',
    '\n', css, flags=re.S,
)
css += r'''

/* PROUDPOPS-ACTUAL-HOME-SERVICE-ACCENTS-V1 */
.pp-actual-home-service-card {
  --pp-service-accent: #49a9d7;
  position: relative !important;
  overflow: hidden !important;
  border: 1px solid color-mix(in srgb,var(--pp-service-accent) 58%,transparent) !important;
  background:
    linear-gradient(180deg,color-mix(in srgb,var(--pp-service-accent) 7%,transparent),transparent 43%),
    #0d141a !important;
  box-shadow:
    0 16px 34px rgba(0,0,0,.22),
    0 0 0 1px color-mix(in srgb,var(--pp-service-accent) 8%,transparent) !important;
  transition: transform .18s ease,border-color .18s ease,background .18s ease,box-shadow .18s ease !important;
}
.pp-actual-home-service-card::before {
  content: "" !important;
  position: absolute !important;
  z-index: 2 !important;
  inset: 0 0 auto !important;
  width: auto !important;
  height: 5px !important;
  background: var(--pp-service-accent) !important;
  border-radius: 0 !important;
}
.pp-actual-home-service-card:hover {
  border-color: color-mix(in srgb,var(--pp-service-accent) 88%,transparent) !important;
  background:
    linear-gradient(180deg,color-mix(in srgb,var(--pp-service-accent) 12%,transparent),transparent 48%),
    #10181f !important;
  box-shadow:
    0 20px 42px rgba(0,0,0,.28),
    0 0 25px color-mix(in srgb,var(--pp-service-accent) 15%,transparent) !important;
  transform: translateY(-3px);
}
.pp-actual-home-service-card.pp-accent-haircut { --pp-service-accent: #49a9d7; }
.pp-actual-home-service-card.pp-accent-beard { --pp-service-accent: #2fb5aa; }
.pp-actual-home-service-card.pp-accent-shave { --pp-service-accent: #55c7d9; }
.pp-actual-home-service-card.pp-accent-enhancement { --pp-service-accent: #798ee8; }
.pp-actual-home-service-card.pp-accent-edgeup { --pp-service-accent: #66c89a; }
@media (prefers-reduced-motion: reduce) {
  .pp-actual-home-service-card { transition: none !important; }
  .pp-actual-home-service-card:hover { transform: none; }
}
/* PROUDPOPS-ACTUAL-HOME-SERVICE-ACCENTS-V1-END */
'''
css_path.write_text('\n'.join(line.rstrip() for line in css.splitlines()).rstrip() + '\n', encoding='utf-8')
PY

log ""
log "=== Validating corrected homepage targeting ==="
for page in "$INDEX" "$STAGED_HOME"; do
  grep -Fq -- 'PROUDPOPS-ACTUAL-HOME-SERVICE-ACCENTS-DEPLOYED-V1' "$page" || fail "Deployment marker missing from $(basename "$page")."
  grep -Fq -- 'pp-actual-home-service-card' "$page" || fail "Targeting script missing from $(basename "$page")."
  grep -Fq -- "section.dataset.serviceAccentCards" "$page" || fail "Runtime card-count marker missing from $(basename "$page")."
done
for required in \
  'PROUDPOPS-ACTUAL-HOME-SERVICE-ACCENTS-V1' \
  '.pp-actual-home-service-card::before' \
  'height: 5px !important' \
  'pp-accent-haircut' 'pp-accent-beard' 'pp-accent-shave' 'pp-accent-enhancement' 'pp-accent-edgeup'
do
  grep -Fq -- "$required" "$SITE_CSS" || fail "site.css validation missing: $required"
done

git diff --check || fail "Git whitespace validation failed."
git add -- public-site/index.html public-site/multipage-index.html public-site/assets/css/site.css
git diff --cached --quiet && fail "No corrected homepage accent changes were staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"
COMMIT_ID="$(git rev-parse --short HEAD)"

log ""
log "=== Publishing corrected homepage accents ==="
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
log "=== Verifying live corrected accent assets ==="
for pair in "/:$WORK_DIR/root.html" "/index.html:$WORK_DIR/index.html" "/multipage-index.html:$WORK_DIR/staged.html"; do
  path="${pair%%:*}"; output="${pair#*:}"
  code="$(curl -sS -L -o "$output" -w '%{http_code}' "https://proudpops.denduluru.com$path?v=$COMMIT_ID-$STAMP")"
  [[ "$code" == "200" ]] || fail "$path returned HTTP $code."
  grep -Fq -- 'PROUDPOPS-ACTUAL-HOME-SERVICE-ACCENTS-DEPLOYED-V1' "$output" || fail "$path is missing the corrected marker."
  grep -Fq -- 'pp-actual-home-service-card' "$output" || fail "$path is missing the card-targeting script."
  log "PASS live homepage: $path"
done
CSS_CODE="$(curl -sS -L -o "$WORK_DIR/site.css" -w '%{http_code}' "https://proudpops.denduluru.com/assets/css/site.css?v=$COMMIT_ID-$STAMP")"
[[ "$CSS_CODE" == "200" ]] || fail "Live site.css returned HTTP $CSS_CODE."
grep -Fq -- 'PROUDPOPS-ACTUAL-HOME-SERVICE-ACCENTS-V1' "$WORK_DIR/site.css" || fail "Live corrected CSS marker is missing."
grep -Fq -- 'height: 5px !important' "$WORK_DIR/site.css" || fail "Live top-accent rule is missing."

if ! git push origin "$BRANCH"; then
  LIVE_REPLACED=0
  fail "Production verified but Git push failed. Retry: git push origin $BRANCH"
fi
LIVE_REPLACED=0
SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean after deployment."

log ""
log "SUCCESS: Homepage service accents now target the actual five cards."
log "Commit: $COMMIT_ID"
log "Backup: $BACKUP_DIR"
log "Homepage: https://proudpops.denduluru.com/"
