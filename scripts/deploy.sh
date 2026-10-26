#!/usr/bin/env bash
# Culture Bridge — redeploy the latest main in one go, with no questions.
#
#   bash scripts/deploy.sh
#
# It pulls main, builds the image (skipped when this commit was built before), upgrades the
# database (Alembic), deploys the new revision without traffic, and moves traffic to it only
# when its /health (which reaches the database) answers. If the check fails after the switch,
# traffic goes back to the previous revision. Then it re-imports the official procedure drafts
# only when backend/app/content/official_procedures.json changed.
# Migrations run first, so they must keep the previous release working (add, don't rename or
# drop). Rolling back by hand and restoring the database: docs/runbooks/rollback-and-restore.md.
#
# Only for an existing setup: the first deployment, secrets and permissions are
# scripts/gcp-setup.sh step 5. NO_PULL=1 deploys the checked-out commit as is; BUILD_WITH=docker
# builds locally and pushes instead of using Cloud Build.
# .github/workflows/deploy.yml runs it that way after CI passes on main (setup: gcp-setup.sh step 8).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${HOME}/.culture-bridge-setup.env"
# Values chosen in gcp-setup.sh; environment variables win (the CI workflow sets them).
declare -A OVERRIDES=()
for key in PROJECT REGION INSTANCE; do
  [[ -n "${!key:-}" ]] && OVERRIDES[${key}]="${!key}"
done
# shellcheck disable=SC1090
[[ -f "${STATE}" ]] && source "${STATE}"
for key in "${!OVERRIDES[@]}"; do printf -v "${key}" '%s' "${OVERRIDES[${key}]}"; done
PROJECT="${PROJECT:-culture-bridge-511321}"
REGION="${REGION:-asia-east1}"
INSTANCE="${INSTANCE:-culturebridge-db}"
BUILD_WITH="${BUILD_WITH:-cloudbuild}"  # cloudbuild (Cloud Shell) or docker (CI runner)
IMAGE_REPO="${REGION}-docker.pkg.dev/${PROJECT}/culture-bridge/app"
SERVICE=culture-bridge
CARDS=backend/app/content/official_procedures.json

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
gc() { gcloud "$@" --project="${PROJECT}"; }

require_login() {
  [[ -n "$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)" ]] \
    && return 0
  die "目前沒有登入的 Google 帳號。執行 gcloud config set account <你的 Google 帳號>（或重新整理 Cloud Shell 頁面並按「授權」），再重新執行 bash scripts/deploy.sh。"
}

service_json() { gc run services describe "${SERVICE}" --region="${REGION}" --format=json; }

# The revision getting the traffic now: the one to go back to.
serving_revision() {
  service_json | python3 -c '
import json, sys
traffic = json.load(sys.stdin)["status"].get("traffic", [])
print(max(traffic, key=lambda t: t.get("percent", 0))["revisionName"])'
}

# The URL of a tagged revision (it answers there even without traffic).
tag_url() {
  service_json | python3 -c '
import json, sys
print(next(t["url"] for t in json.load(sys.stdin)["status"]["traffic"] if t.get("tag") == sys.argv[1]))' "$1"
}

# /health answers 200 only when the app is up and reaches the database. A new revision starts
# cold, so a few tries.
check_health() {
  local answer
  if answer="$(curl -fsS --retry 5 --retry-delay 6 --retry-all-errors --max-time 20 \
    "$1/health" 2>&1)"; then
    note "健康檢查：${answer}"
  else
    note "健康檢查失敗：${answer}"
    return 1
  fi
}

command -v gcloud >/dev/null || die "找不到 gcloud；請在 Google Cloud Shell 執行。"
require_login
cd "${REPO_ROOT}"

if [[ "${NO_PULL:-0}" != "1" ]]; then
  bold "1/5 取得最新的 main"
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] \
    || die "這個資料夾有改過的檔案，先處理掉（例如 git stash）再部署。"
  git checkout -q main
  git pull -q --ff-only origin main
fi
tag="$(git rev-parse --short HEAD)"
image="${IMAGE_REPO}:${tag}"
note "版本：${tag}  $(git log -1 --format=%s)"

# The commit currently live, to tell whether the procedure cards changed.
if ! live_image="$(gc run services describe "${SERVICE}" --region="${REGION}" \
  --format='value(spec.template.spec.containers[0].image)' 2>&1)"; then
  printf '%s\n' "${live_image}" >&2
  if [[ "${live_image}" == *"could not be found"* || "${live_image}" == *NOT_FOUND* ]]; then
    die "找不到 ${SERVICE} 服務。第一次部署請用 bash scripts/gcp-setup.sh 5。"
  fi
  die "讀不到 ${SERVICE} 服務（上面是 Google Cloud 的錯誤訊息）。在 GitHub Actions 出現時，通常是 gcp-setup.sh 步驟 8 沒有完整跑完：重跑 bash scripts/gcp-setup.sh 8。"
fi
live_tag="${live_image##*:}"

bold "2/5 映像檔"
if gcloud artifacts docker images describe "${image}" >/dev/null 2>&1; then
  note "${tag} 已經建置過，略過。"
elif [[ "${BUILD_WITH}" == "docker" ]]; then
  gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
  docker build -t "${image}" .
  docker push "${image}"
else
  note "Cloud Build 約 5–10 分鐘。"
  gc builds submit "${REPO_ROOT}" --tag="${image}" --machine-type=e2-highcpu-8
  require_login  # Cloud Shell tends to drop its login during the build
fi

bold "3/5 資料表（Alembic）"
gc run jobs update culture-bridge-migrate --image="${image}" --region="${REGION}" --quiet
gc run jobs execute culture-bridge-migrate --region="${REGION}" --wait

bold "4/5 部署（新版本先不給流量，健康檢查通過才切換）"
old_rev="$(serving_revision)"
# Only the image changes; secrets, Cloud SQL, environment and access stay as step 5 set them.
gc run deploy "${SERVICE}" --image="${image}" --region="${REGION}" \
  --no-traffic --tag=candidate --quiet
new_rev="$(gc run services describe "${SERVICE}" --region="${REGION}" \
  --format='value(status.latestCreatedRevisionName)')"
candidate_url="$(tag_url candidate)"   || die "找不到新版本 ${new_rev} 的 candidate 網址，流量仍在 ${old_rev}。"
if ! check_health "${candidate_url}"; then
  die "新版本 ${new_rev} 沒通過健康檢查，流量仍在 ${old_rev}，使用者不受影響。到 Cloud Run → 修訂版本 → ${new_rev} → 記錄查原因。"
fi
gc run services update-traffic "${SERVICE}" --region="${REGION}" --to-latest --quiet
url="$(gc run services describe "${SERVICE}" --region="${REGION}" --format='value(status.url)')"
if ! check_health "${url}"; then
  gc run services update-traffic "${SERVICE}" --region="${REGION}" \
    --to-revisions="${old_rev}=100" --quiet
  die "切換到 ${new_rev} 後健康檢查失敗，已把流量退回 ${old_rev}。"
fi
note "流量已切到 ${new_rev}（上一版 ${old_rev}，要退回見 docs/runbooks/rollback-and-restore.md）。"

bold "5/5 官方流程卡"
if [[ "${live_tag}" == "${tag}" ]] || git diff --quiet "${live_tag}" HEAD -- "${CARDS}" 2>/dev/null; then
  note "流程卡檔案沒有變更，不用重新匯入。"
else
  note "流程卡檔案有變更（${live_tag} → ${tag}），更新沒人編輯過的草稿。"
  gc run jobs update culture-bridge-import --image="${image}" --region="${REGION}" --quiet
  gc run jobs execute culture-bridge-import --region="${REGION}" --wait
fi

bold "完成：${url}"
note "版本 ${tag}（${new_rev}）"
