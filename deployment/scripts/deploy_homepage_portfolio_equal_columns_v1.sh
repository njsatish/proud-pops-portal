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
COMMIT_MESSAGE="Use equal columns for homepage portfolio photos"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Downloads/proudpops-backups/home-portfolio-equal-columns-$STAMP"
WORK_DIR="$(mktemp -d)"
LIVE_REPLACED=0
SUCCESS=0

log(){ printf '%s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_state(){ sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1; }
aws_cmd(){ aws --profile "$AWS_PROFILE_NAME" --region "$REGION" "$@"; }

restore_live(){
  [[ "$LIVE_REPLACED" -eq 1 ]] || return 0
  log "Restoring previous live homepages and stylesheet..."
  for file in index.html multipage-index.html; do
    [[ -s "$BACKUP_DIR/s3-$file" ]] || continue
    aws_cmd s3 cp "$BACKUP_DIR/s3-$file" "s3://$BUCKET_NAME/$file" \
      --content-type 'text/html; charset=utf-8' \
      --cache-control 'no-cache,no-store,must-revalidate' >/dev/null || true
  done
  if [[ -s "$BACKUP_DIR/s3-site.css" ]]; then
    aws_cmd s3 cp "$BACKUP_DIR/s3-site.css" "s3://$BUCKET_NAME/assets/css/site.css" \
      --content-type 'text/css; charset=utf-8' \
      --cache-control 'public,max-age=300,must-revalidate' >/dev/null || true
  fi
  local rollback_id
  rollback_id="$(aws_cmd cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" \
    --paths '/' '/index.html' '/multipage-index.html' '/assets/css/site.css' \
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

log "=== Proud Pops Homepage Portfolio Equal Columns V1 ==="
log "Desktop: 3 equal columns"
log "Tablet: 2 columns with the third image centered below"
log "Mobile: 3 full-width stacked images"

[[ -d "$REPO/.git" ]] || fail "Git repository not found: $REPO"
[[ -s "$INDEX" ]] || fail "Homepage is missing: $INDEX"
[[ -s "$STAGED_HOME" ]] || fail "Staged homepage is missing: $STAGED_HOME"
[[ -s "$SITE_CSS" ]] || fail "Shared stylesheet is missing: $SITE_CSS"
[[ -f "$STATE_FILE" ]] || fail "AWS deployment state is missing: $STATE_FILE"
command -v python3 >/dev/null 2>&1 || fail "python3 is required."

for page in "$INDEX" "$STAGED_HOME"; do
  grep -Fq -- 'Detail you can see.' "$page" || fail "Portfolio heading is missing from $(basename "$page")."
  grep -Fq -- 'View Full Gallery' "$page" || fail "Gallery link is missing from $(basename "$page")."
done

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
START = '<!-- PROUDPOPS-HOME-PORTFOLIO-EQUAL-COLUMNS-V1-START -->'
END = '<!-- PROUDPOPS-HOME-PORTFOLIO-EQUAL-COLUMNS-V1-END -->'
MARKER = '<!-- PROUDPOPS-HOME-PORTFOLIO-EQUAL-COLUMNS-DEPLOYED-V1 -->'

runtime_script = START + r'''
<script>
(() => {
  const normalize = value => (value || '').replace(/\s+/g, ' ').trim().toLowerCase();
  const heading = [...document.querySelectorAll('h1,h2,h3')]
    .find(node => normalize(node.textContent).includes('detail you can see'));
  const section = heading ? heading.closest('section') : null;
  if (!section) return;

  const images = [...section.querySelectorAll('img')].slice(0, 3);
  if (images.length !== 3) return;

  const wrappers = images.map(image => {
    let node = image.parentElement;
    while (node && node !== section) {
      if (node.querySelectorAll('img').length === 1) return node;
      node = node.parentElement;
    }
    return image;
  });

  let grid = wrappers[0].parentElement;
  while (grid && grid !== section) {
    if (wrappers.every(wrapper => grid.contains(wrapper))) break;
    grid = grid.parentElement;
  }
  if (!grid || grid === section) return;

  grid.classList.add('pp-home-portfolio-equal-grid');
  wrappers.forEach((wrapper, index) => {
    wrapper.classList.add('pp-home-portfolio-equal-item');
    wrapper.dataset.portfolioEqualIndex = String(index + 1);
    images[index].classList.add('pp-home-portfolio-equal-image');
  });
  section.dataset.portfolioEqualColumns = '3';
})();
</script>
''' + END

for path in home_paths:
    text = path.read_text(encoding='utf-8')
    pattern = re.compile(re.escape(START) + r'.*?' + re.escape(END), re.S)
    if pattern.search(text):
        text = pattern.sub(runtime_script, text, count=1)
    else:
        if '</body>' not in text:
            raise SystemExit(f'ERROR: closing body tag missing in {path.name}')
        text = text.replace('</body>', runtime_script + '\n</body>', 1)
    if MARKER not in text:
        text = text.replace('</head>', '  ' + MARKER + '\n</head>', 1)
    path.write_text('\n'.join(line.rstrip() for line in text.splitlines()).rstrip() + '\n', encoding='utf-8')

css = css_path.read_text(encoding='utf-8')
css = re.sub(
    r'\n?/\* PROUDPOPS-HOME-PORTFOLIO-EQUAL-COLUMNS-V1 \*/.*?'
    r'/\* PROUDPOPS-HOME-PORTFOLIO-EQUAL-COLUMNS-V1-END \*/\n?',
    '\n',
    css,
    flags=re.S,
)
css += r'''

/* PROUDPOPS-HOME-PORTFOLIO-EQUAL-COLUMNS-V1 */
.pp-home-portfolio-equal-grid {
  width: 100% !important;
  display: grid !important;
  grid-template-columns: repeat(3, minmax(0, 1fr)) !important;
  grid-template-rows: none !important;
  gap: 18px !important;
  align-items: stretch !important;
}

.pp-home-portfolio-equal-item {
  width: 100% !important;
  min-width: 0 !important;
  height: auto !important;
  min-height: 0 !important;
  grid-column: auto !important;
  grid-row: auto !important;
  aspect-ratio: 4 / 5 !important;
  overflow: hidden !important;
  border-radius: 18px !important;
}

.pp-home-portfolio-equal-image {
  width: 100% !important;
  height: 100% !important;
  min-height: 0 !important;
  display: block !important;
  object-fit: cover !important;
  object-position: center !important;
  border-radius: inherit !important;
}

.pp-home-portfolio-equal-item[data-portfolio-equal-index="3"] .pp-home-portfolio-equal-image {
  object-position: 52% center !important;
}

@media (max-width: 900px) and (min-width: 621px) {
  .pp-home-portfolio-equal-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
  }

  .pp-home-portfolio-equal-item[data-portfolio-equal-index="3"] {
    width: min(50%, 560px) !important;
    grid-column: 1 / -1 !important;
    justify-self: center !important;
  }
}

@media (max-width: 620px) {
  .pp-home-portfolio-equal-grid {
    grid-template-columns: minmax(0, 1fr) !important;
    gap: 14px !important;
  }

  .pp-home-portfolio-equal-item,
  .pp-home-portfolio-equal-item[data-portfolio-equal-index="3"] {
    width: 100% !important;
    grid-column: auto !important;
    aspect-ratio: 4 / 5 !important;
  }
}
/* PROUDPOPS-HOME-PORTFOLIO-EQUAL-COLUMNS-V1-END */
'''
css_path.write_text('\n'.join(line.rstrip() for line in css.splitlines()).rstrip() + '\n', encoding='utf-8')
PY

log ""
log "=== Validating equal-column Portfolio patch ==="
for page in "$INDEX" "$STAGED_HOME"; do
  grep -Fq -- 'PROUDPOPS-HOME-PORTFOLIO-EQUAL-COLUMNS-DEPLOYED-V1' "$page" || fail "Marker missing from $(basename "$page")."
  grep -Fq -- 'pp-home-portfolio-equal-grid' "$page" || fail "Runtime targeting script missing from $(basename "$page")."
  grep -Fq -- "section.dataset.portfolioEqualColumns = '3'" "$page" || fail "Runtime card-count marker missing from $(basename "$page")."
done
for required in \
  'PROUDPOPS-HOME-PORTFOLIO-EQUAL-COLUMNS-V1' \
  '.pp-home-portfolio-equal-grid' \
  'grid-template-columns: repeat(3, minmax(0, 1fr))' \
  'aspect-ratio: 4 / 5' \
  'object-fit: cover' \
  'object-position: 52% center'
do
  grep -Fq -- "$required" "$SITE_CSS" || fail "site.css validation missing: $required"
done

git diff --check || fail "Git whitespace validation failed."
git add -- public-site/index.html public-site/multipage-index.html public-site/assets/css/site.css
git diff --cached --quiet && fail "No equal-column Portfolio changes were staged."
git diff --cached --check
git commit -m "$COMMIT_MESSAGE"
COMMIT_ID="$(git rev-parse --short HEAD)"

log ""
log "=== Publishing equal-column Portfolio layout ==="
for file in index.html multipage-index.html; do
  aws_cmd s3 cp "$PUBLIC_SITE/$file" "s3://$BUCKET_NAME/$file" \
    --content-type 'text/html; charset=utf-8' \
    --cache-control 'no-cache,no-store,must-revalidate'
done
aws_cmd s3 cp "$SITE_CSS" "s3://$BUCKET_NAME/assets/css/site.css" \
  --content-type 'text/css; charset=utf-8' \
  --cache-control 'public,max-age=300,must-revalidate'
LIVE_REPLACED=1

INVALIDATION_ID="$(aws_cmd cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths '/' '/index.html' '/multipage-index.html' '/assets/css/site.css' \
  --query 'Invalidation.Id' --output text)"
log "CloudFront invalidation: $INVALIDATION_ID"
aws_cmd cloudfront wait invalidation-completed \
  --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

log ""
log "=== Verifying live equal-column Portfolio assets ==="
for pair in "/:$WORK_DIR/root.html" "/index.html:$WORK_DIR/index.html" "/multipage-index.html:$WORK_DIR/staged.html"; do
  path="${pair%%:*}"
  output="${pair#*:}"
  code="$(curl -sS -L -o "$output" -w '%{http_code}' "https://proudpops.denduluru.com$path?v=$COMMIT_ID-$STAMP")"
  [[ "$code" == "200" ]] || fail "$path returned HTTP $code."
  grep -Fq -- 'PROUDPOPS-HOME-PORTFOLIO-EQUAL-COLUMNS-DEPLOYED-V1' "$output" || fail "$path is missing the deployment marker."
  grep -Fq -- 'pp-home-portfolio-equal-grid' "$output" || fail "$path is missing the Portfolio targeting script."
  grep -Fq -- 'View Full Gallery' "$output" || fail "$path lost View Full Gallery."
  log "PASS live homepage: $path"
done

CSS_CODE="$(curl -sS -L -o "$WORK_DIR/site.css" -w '%{http_code}' "https://proudpops.denduluru.com/assets/css/site.css?v=$COMMIT_ID-$STAMP")"
[[ "$CSS_CODE" == "200" ]] || fail "Live site.css returned HTTP $CSS_CODE."
grep -Fq -- 'PROUDPOPS-HOME-PORTFOLIO-EQUAL-COLUMNS-V1' "$WORK_DIR/site.css" || fail "Live equal-column CSS marker is missing."
grep -Fq -- 'grid-template-columns: repeat(3, minmax(0, 1fr))' "$WORK_DIR/site.css" || fail "Live three-column rule is missing."

for page in /book.html /services.html /about.html /gallery.html /contact.html; do
  code="$(curl -sS -L -o /dev/null -w '%{http_code}' "https://proudpops.denduluru.com$page?protected=$STAMP")"
  [[ "$code" == "200" ]] || fail "$page returned HTTP $code."
done

log ""
log "=== Pushing verified equal-column Portfolio commit ==="
if ! git push origin "$BRANCH"; then
  LIVE_REPLACED=0
  fail "Production verified but Git push failed. Retry: git push origin $BRANCH"
fi

LIVE_REPLACED=0
SUCCESS=1
[[ -z "$(git status --porcelain)" ]] || fail "Repository is not clean after deployment."

log ""
log "SUCCESS: Homepage Portfolio now uses three equal photo columns."
log "Commit: $COMMIT_ID"
log "Desktop: 3 equal columns"
log "Tablet: 2 columns plus centered third image"
log "Mobile: 3 full-width stacked images"
log "Backup: $BACKUP_DIR"
log "Homepage: https://proudpops.denduluru.com/"
