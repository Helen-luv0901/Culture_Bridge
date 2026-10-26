#!/usr/bin/env bash
# Culture Bridge — Google Cloud setup, step by step (work-assignment A-1, A-2, A-3, A-5, A-7, A-8).
#
# Run in Google Cloud Shell (https://shell.cloud.google.com), already signed in as you:
#   git clone https://github.com/Helen-luv0901/Culture_Bridge && cd Culture_Bridge
#   bash scripts/gcp-setup.sh            # menu
#   DRY_RUN=1 bash scripts/gcp-setup.sh  # only print what would run
#   AUTO=1 OLD_INSTANCE=… bash scripts/gcp-setup.sh 2   # no Enter pauses; values from env/state
#
# Every command is shown before it runs and waits for Enter. Steps that cost money or cannot be
# undone ask you to type "yes". Choices are remembered in ~/.culture-bridge-setup.env (no secrets).
# Details for each step: docs/runbooks/a3-…, a5-…, a7-deploy-cloud-run.md.

set -euo pipefail

STATE="${HOME}/.culture-bridge-setup.env"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"
AUTO="${AUTO:-0}"  # 1 = run commands without waiting for Enter (typing "yes" is still required)
STATE_KEYS=(PROJECT REGION OLD_INSTANCE INSTANCE DB DB_VERSION BUCKET SA IMAGE_REPO
  FIREBASE_WEB_API_KEY FIREBASE_WEB_APP_ID FIREBASE_AUTH_DOMAIN FIREBASE_MESSAGING_SENDER_ID
  SERVICE_URL ALERT_EMAIL)

# ---------- helpers ----------

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# Show a command, wait for Enter (s = skip), then run it.
run() {
  local shown="$*"
  # Never print passwords or access tokens in the echoed command.
  shown="$(printf '%s' "${shown}" \
    | sed -E 's/(--password=)[^ ]+/\1********/g; s/(Bearer )[^ ]+/\1********/g')"
  printf '\n  $ %s\n' "${shown}"
  if [[ "${DRY_RUN}" == "1" ]]; then note "(DRY_RUN: not executed)"; return 0; fi
  if [[ "${AUTO}" != "1" ]]; then
    read -r -p "  Enter 執行 / s 略過: " answer
    [[ "${answer}" == "s" ]] && { note "略過"; return 0; }
  fi
  if ! "$@"; then
    printf '\n\033[31m  上面的指令失敗，這一步先停在這裡。修正後可重新執行這一步。\033[0m\n' >&2
    exit 1
  fi
}

# Cloud Shell sometimes loses its credentials, often during the 5-10 minute build. Stop with the
# fix instead of failing on the next command (and misreading "describe failed" as "missing").
require_login() {
  [[ "${DRY_RUN}" == "1" ]] && return 0
  [[ -n "$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)" ]] \
    && return 0
  die "Cloud Shell 目前沒有登入的帳號。執行 gcloud config set account <你的 Google 帳號>，或重新整理 Cloud Shell 頁面並按「授權」，再重新執行這一步。"
}

# Run a command whose output may contain a secret (e.g. api-keys create prints keyString even
# with --format=none). Shows nothing on success; on failure shows the error with keys masked.
hide_output() {
  local output
  if output="$("$@" 2>&1)"; then return 0; fi
  printf '%s\n' "${output}" \
    | sed -E 's/AIza[0-9A-Za-z_-]+/********/g; s/("?keyString"?[:=] *"?)[^",[:space:]]+/\1********/g' >&2
  return 1
}

# For anything that costs money or cannot be undone.
confirm_yes() {
  printf '\n\033[33m%s\033[0m\n' "$1"
  if [[ "${DRY_RUN}" == "1" ]]; then note "(DRY_RUN: assuming yes)"; return 0; fi
  read -r -p "  確定請輸入 yes: " answer
  [[ "${answer}" == "yes" ]]
}

ask() {  # ask VAR "question" [default]
  local var="$1" question="$2" default="${3:-}" current="${!1:-}"
  local shown="${current:-${default}}"
  if [[ "${AUTO}" == "1" && -n "${shown}" ]]; then
    printf -v "${var}" '%s' "${shown}"
    note "${question}: ${shown}"
    save_state
    return 0
  fi
  read -r -p "  ${question}${shown:+ [${shown}]}: " value
  printf -v "${var}" '%s' "${value:-${shown}}"
  save_state
}

save_state() {
  {
    for key in "${STATE_KEYS[@]}"; do
      printf '%s=%q\n' "${key}" "${!key:-}"
    done
  } >"${STATE}"
}

# Values given on the command line (PROJECT=… bash …) win over the saved ones.
declare -A OVERRIDES=()
for key in "${STATE_KEYS[@]}"; do [[ -n "${!key:-}" ]] && OVERRIDES[${key}]="${!key}"; done
# shellcheck disable=SC1090
[[ -f "${STATE}" ]] && source "${STATE}"
for key in "${!OVERRIDES[@]}"; do printf -v "${key}" '%s' "${OVERRIDES[${key}]}"; done
PROJECT="${PROJECT:-culture-bridge}"
REGION="${REGION:-asia-east1}"
DB="${DB:-culturebridge}"

secret_exists() { gcloud secrets describe "$1" --project="${PROJECT}" >/dev/null 2>&1; }

# Store a secret read from stdin, creating it or adding a new version. Never echoes the value.
put_secret() {
  local name="$1"
  if [[ "${DRY_RUN}" == "1" ]]; then note "(DRY_RUN: would store secret ${name})"; cat >/dev/null; return 0; fi
  if secret_exists "${name}"; then
    gcloud secrets versions add "${name}" --project="${PROJECT}" --data-file=- >/dev/null
  else
    gcloud secrets create "${name}" --project="${PROJECT}" --replication-policy=automatic \
      --data-file=- >/dev/null
  fi
  note "已存入 Secret Manager：${name}"
}

need_instance() {
  [[ -n "${INSTANCE:-}" ]] || ask INSTANCE "要使用的 Cloud SQL 執行個體名稱" "culturebridge-db"
}

# Give the new instance's postgres user a fresh password, store the backend's connection string
# in Secret Manager (database-url) and show the password once for teammates who use Cloud SQL Studio.
set_owner_password() {
  if secret_exists database-url; then
    note "database-url 已存在，沿用原本的 postgres 密碼。"
    note "（查看：gcloud secrets versions access latest --secret=database-url）"
    return 0
  fi
  local password
  password="$(openssl rand -base64 24 | tr -d '/+=' | head -c 28)"
  run gcloud sql users set-password postgres --instance="${INSTANCE}" --project="${PROJECT}" \
    --password="${password}"
  [[ "${DRY_RUN}" == "1" ]] && return 0
  printf 'postgresql+psycopg://postgres:%s@/%s?host=/cloudsql/%s:%s:%s' \
    "${password}" "${DB}" "${PROJECT}" "${REGION}" "${INSTANCE}" | put_secret database-url
  note "新執行個體 postgres 的密碼（只顯示這一次，請私下交給需要直接連資料庫的組員，不要貼到任何對話或截圖）："
  note "    ${password}"
  note "忘記時可以查：gcloud secrets versions access latest --secret=database-url"
}

# ---------- 0. project ----------

step_project() {
  bold "0. 專案與 API"
  note "你的專案：（找不到時用 gcloud projects list 確認 PROJECT_ID）"
  gcloud projects list --format='value(projectId)' 2>/dev/null | sed 's/^/    /' || true
  ask PROJECT "Google Cloud 專案 ID" "${PROJECT}"
  gcloud projects describe "${PROJECT}" >/dev/null 2>&1 \
    || die "找不到專案 ${PROJECT}，請重新執行步驟 0 並輸入上面列出的其中一個 ID。"
  ask REGION "區域" "${REGION}"
  run gcloud config set project "${PROJECT}"
  run gcloud services enable sqladmin.googleapis.com run.googleapis.com \
    cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com \
    generativelanguage.googleapis.com apikeys.googleapis.com firebase.googleapis.com \
    identitytoolkit.googleapis.com monitoring.googleapis.com billingbudgets.googleapis.com \
    --project="${PROJECT}"
}

# ---------- 1. budget alert (A-1) ----------

step_budget() {
  bold "1. 費用警報（A-1）"
  local account
  account="$(gcloud billing projects describe "${PROJECT}" --format='value(billingAccountName)' 2>/dev/null || true)"
  [[ -n "${account}" ]] || die "找不到這個專案的帳單帳戶，請先在主控台連結帳單帳戶。"
  note "帳單帳戶：${account}"
  local amount
  read -r -p "  每月預算（含幣別，例如 1000TWD；要和帳單帳戶幣別相同）: " amount
  [[ -n "${amount}" ]] || { note "略過"; return 0; }
  run gcloud billing budgets create --billing-account="${account#billingAccounts/}" \
    --display-name="culture-bridge monthly" --budget-amount="${amount}" \
    --filter-projects="projects/${PROJECT}" \
    --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
  note "達到 50%、90%、100% 時會寄信給帳單帳戶管理者。"
}

# ---------- 2. database migration (A-3, A-2) ----------

step_database() {
  bold "2. Cloud SQL：從試用執行個體搬到最小規格（A-3，期限 11/10）"
  note "目前的執行個體："
  gcloud sql instances list --project="${PROJECT}" \
    --format='table(name,databaseVersion,settings.edition,settings.tier,state)' || true
  ask OLD_INSTANCE "試用執行個體（舊）名稱" "${OLD_INSTANCE:-}"
  ask INSTANCE "新執行個體名稱" "${INSTANCE:-culturebridge-db}"
  ask DB "資料庫名稱" "${DB}"
  DB_VERSION="$(gcloud sql instances describe "${OLD_INSTANCE}" --project="${PROJECT}" \
    --format='value(databaseVersion)')"
  note "舊執行個體版本：${DB_VERSION}（新的用同一版）"
  BUCKET="${BUCKET:-gs://${PROJECT}-sql-migration}"
  save_state

  bold "2a. 匯出舊資料庫"
  note "匯出前請通知組員不要寫入資料庫。"
  gcloud storage buckets describe "${BUCKET}" >/dev/null 2>&1 \
    || run gcloud storage buckets create "${BUCKET}" --project="${PROJECT}" \
      --location="${REGION}" --uniform-bucket-level-access
  local old_sa
  old_sa="$(gcloud sql instances describe "${OLD_INSTANCE}" --project="${PROJECT}" \
    --format='value(serviceAccountEmailAddress)')"
  run gcloud storage buckets add-iam-policy-binding "${BUCKET}" \
    --member="serviceAccount:${old_sa}" --role=roles/storage.objectAdmin
  run gcloud sql export sql "${OLD_INSTANCE}" "${BUCKET}/${DB}.sql.gz" \
    --database="${DB}" --project="${PROJECT}"

  bold "2b. 建立新執行個體"
  if gcloud sql instances describe "${INSTANCE}" --project="${PROJECT}" >/dev/null 2>&1; then
    note "${INSTANCE} 已存在，略過建立。"
  else
    confirm_yes "會建立 Enterprise 版 db-f1-micro 執行個體（開始計費，費用以主控台估價為準；目前由試用額度支付）。" \
      || { note "已取消"; return 0; }
    run gcloud sql instances create "${INSTANCE}" --project="${PROJECT}" \
      --database-version="${DB_VERSION}" --edition=ENTERPRISE --tier=db-f1-micro \
      --region="${REGION}" --availability-type=zonal --storage-size=10 \
      --backup-start-time=18:00 --enable-point-in-time-recovery --retained-transaction-log-days=7
    run gcloud sql databases create "${DB}" --instance="${INSTANCE}" --project="${PROJECT}"
  fi

  bold "2c. 資料庫帳號"
  note "舊執行個體的帳號（資料表的擁有者通常是 postgres）："
  gcloud sql users list --instance="${OLD_INSTANCE}" --project="${PROJECT}" \
    --format='value(name)' | sed 's/^/    /'
  note "新執行個體沿用 postgres 當資料表擁有者：匯入、migration 和後端都用它，權限才一致。"
  note "（另外替組員建帳號的話，那些帳號沒有資料表權限，所以這裡不建。）"
  set_owner_password

  bold "2d. 匯入"
  local new_sa
  new_sa="$(gcloud sql instances describe "${INSTANCE}" --project="${PROJECT}" \
    --format='value(serviceAccountEmailAddress)' 2>/dev/null || echo "<new-instance-sa>")"
  run gcloud storage buckets add-iam-policy-binding "${BUCKET}" \
    --member="serviceAccount:${new_sa}" --role=roles/storage.objectViewer
  run gcloud sql import sql "${INSTANCE}" "${BUCKET}/${DB}.sql.gz" \
    --database="${DB}" --user=postgres --project="${PROJECT}"

  bold "2e. 連線設定與備份（A-2）"
  local ips=""
  [[ "${AUTO}" == "1" ]] || read -r -p "  允許連線的 IP（逗號分隔，例如 1.2.3.4/32；Enter 略過）: " ips
  [[ -n "${ips}" ]] && run gcloud sql instances patch "${INSTANCE}" --project="${PROJECT}" \
    --authorized-networks="${ips}"
  gcloud sql instances describe "${INSTANCE}" --project="${PROJECT}" \
    --format='value(settings.backupConfiguration.enabled)' 2>/dev/null | grep -qi true \
    && note "自動備份：已開啟" \
    || run gcloud sql instances patch "${INSTANCE}" --project="${PROJECT}" --backup-start-time=18:00

  bold "2f. 驗證"
  note "請用 Cloud SQL Studio（主控台 → SQL → ${INSTANCE} → Cloud SQL Studio）執行："
  note "  SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"
  note "  SELECT count(*) FROM topics;   -- 每張有資料的表都和舊的比對"
  note "確認無誤、新的連線資訊交給組員之後，再回來執行選單 9 刪除舊執行個體與匯出檔。"
}

step_cleanup_old() {
  bold "9. 刪除舊的試用執行個體與匯出檔（確認新資料庫正常後才做）"
  [[ -n "${OLD_INSTANCE:-}" ]] || ask OLD_INSTANCE "舊執行個體名稱"
  confirm_yes "會永久刪除 ${OLD_INSTANCE} 與其中所有資料，無法復原。" || { note "已取消"; return 0; }
  run gcloud sql instances delete "${OLD_INSTANCE}" --project="${PROJECT}"
  [[ -n "${BUCKET:-}" ]] && run gcloud storage rm --recursive "${BUCKET}"
}

# ---------- 3. Gemini API key (A-5) ----------

step_gemini() {
  bold "3. Gemini 金鑰（A-5）"
  note "金鑰只會存進 Secret Manager（gemini-api-key），不會顯示在畫面上。"
  local name
  name="$(gcloud services api-keys list --project="${PROJECT}" \
    --filter='displayName=culture-bridge-backend' --format='value(name)' 2>/dev/null | head -n1)"
  if [[ -z "${name}" ]]; then
    run hide_output gcloud services api-keys create --project="${PROJECT}" \
      --display-name=culture-bridge-backend \
      --api-target=service=generativelanguage.googleapis.com --format=none
    name="$(gcloud services api-keys list --project="${PROJECT}" \
      --filter='displayName=culture-bridge-backend' --format='value(name)' 2>/dev/null | head -n1)"
  else
    note "金鑰 culture-bridge-backend 已存在，沿用並只允許 Gemini API。"
  fi
  if [[ "${DRY_RUN}" != "1" ]]; then
    [[ -n "${name}" ]] || die "找不到剛建立的金鑰。"
    gcloud services api-keys get-key-string "${name}" --format='value(keyString)' \
      | tr -d '\n' | put_secret gemini-api-key
  fi
  note "接著請到 Google Cloud 主控台 → API 和服務 → Generative Language API → 配額，把每日請求數調到合理值。"
  note "【確認】專案已連結帳單帳戶時，Gemini API 走付費方案（Google 不以內容訓練模型）；請把結果告訴 D 寫進隱私權政策。"
}

# ---------- 4. Firebase sign-in ----------

firebase_api() {  # firebase_api METHOD PATH [JSON]
  local token
  token="$(gcloud auth print-access-token)"
  curl -fsS -X "$1" "https://firebase.googleapis.com/v1beta1/$2" \
    -H "Authorization: Bearer ${token}" -H "x-goog-user-project: ${PROJECT}" \
    -H 'Content-Type: application/json' ${3:+-d "$3"}
}

step_firebase() {
  bold "4. Firebase 登入"
  if ! firebase_api GET "projects/${PROJECT}" >/dev/null 2>&1; then
    run firebase_api POST "projects/${PROJECT}:addFirebase" '{}'
    note "Firebase 加入專案需要約一分鐘。"
  else
    note "這個專案已經有 Firebase。"
  fi
  local app
  app="$(firebase_api GET "projects/${PROJECT}/webApps" 2>/dev/null \
    | python3 -c 'import json,sys; a=json.load(sys.stdin).get("apps",[]); print(a[0]["appId"] if a else "")' || true)"
  if [[ -z "${app}" ]]; then
    run firebase_api POST "projects/${PROJECT}/webApps" '{"displayName":"Culture Bridge Web"}'
    sleep 10
    app="$(firebase_api GET "projects/${PROJECT}/webApps" \
      | python3 -c 'import json,sys; a=json.load(sys.stdin).get("apps",[]); print(a[0]["appId"] if a else "")')"
  fi
  if [[ -n "${app}" && "${DRY_RUN}" != "1" ]]; then
    eval "$(firebase_api GET "projects/${PROJECT}/webApps/${app}/config" | python3 -c '
import json, shlex, sys
c = json.load(sys.stdin)
for k, v in {"FIREBASE_WEB_API_KEY": "apiKey", "FIREBASE_WEB_APP_ID": "appId",
             "FIREBASE_AUTH_DOMAIN": "authDomain",
             "FIREBASE_MESSAGING_SENDER_ID": "messagingSenderId"}.items():
    print(k + "=" + shlex.quote(c.get(v) or ""))')"
    save_state
    note "已取得 Firebase 網頁設定（公開識別資訊）：${FIREBASE_AUTH_DOMAIN}"
  fi
  bold "4b. 開啟 Google 登入（需要你在主控台按一下）"
  note "1. 打開 https://console.firebase.google.com/project/${PROJECT}/authentication/providers"
  note "2. 按「開始使用」（第一次才有）→ 選 Google → 啟用 → 選支援 Email → 儲存"
  [[ "${DRY_RUN}" == "1" ]] || read -r -p "  完成後按 Enter: " _
}

add_authorized_domain() {  # Firebase Auth must allow the site's domain for Google sign-in
  local domain="$1" token current
  token="$(gcloud auth print-access-token)"
  current="$(curl -fsS "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT}/config" \
    -H "Authorization: Bearer ${token}" -H "x-goog-user-project: ${PROJECT}")"
  local body
  body="$(python3 -c '
import json, sys
config, domain = json.loads(sys.argv[1]), sys.argv[2]
domains = config.get("authorizedDomains", [])
print(json.dumps({"authorizedDomains": domains + ([domain] if domain not in domains else [])}))' \
    "${current}" "${domain}")"
  run curl -fsS -X PATCH \
    "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT}/config?updateMask=authorizedDomains" \
    -H "Authorization: Bearer ${token}" -H "x-goog-user-project: ${PROJECT}" \
    -H 'Content-Type: application/json' -d "${body}" -o /dev/null
}

# ---------- 5. deploy (A-7, A-9) ----------

step_deploy() {
  bold "5. 部署網頁版與後端到 Cloud Run（A-7）"
  need_instance
  local conn="${PROJECT}:${REGION}:${INSTANCE}"
  SA="culture-bridge-run@${PROJECT}.iam.gserviceaccount.com"
  IMAGE_REPO="${REGION}-docker.pkg.dev/${PROJECT}/culture-bridge/app"
  save_state

  bold "5a. 服務帳戶與權限"
  gcloud iam service-accounts describe "${SA}" --project="${PROJECT}" >/dev/null 2>&1 \
    || run gcloud iam service-accounts create culture-bridge-run --project="${PROJECT}" \
      --display-name="Culture Bridge Cloud Run"
  run gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${SA}" --role=roles/cloudsql.client --condition=None --quiet

  bold "5b. 資料庫連線秘密（postgres 帳號，步驟 2 建立）"
  set_owner_password
  for secret in database-url gemini-api-key; do
    secret_exists "${secret}" || { note "缺少 ${secret}，請先完成步驟 3。"; continue; }
    run gcloud secrets add-iam-policy-binding "${secret}" --project="${PROJECT}" \
      --member="serviceAccount:${SA}" --role=roles/secretmanager.secretAccessor --quiet
  done

  bold "5c. 建置映像檔（Cloud Build，約 5–10 分鐘）"
  gcloud artifacts repositories describe culture-bridge --location="${REGION}" \
    --project="${PROJECT}" >/dev/null 2>&1 \
    || run gcloud artifacts repositories create culture-bridge --repository-format=docker \
      --location="${REGION}" --project="${PROJECT}"
  # New projects run Cloud Build as the default Compute service account, which cannot read the
  # uploaded source without this role (403 storage.objects.get). Granting it again is harmless.
  local project_number
  project_number="$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)')"
  run gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${project_number}-compute@developer.gserviceaccount.com" \
    --role=roles/cloudbuild.builds.builder --condition=None --quiet
  local tag
  tag="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
  if gcloud artifacts docker images describe "${IMAGE_REPO}:${tag}" >/dev/null 2>&1; then
    note "映像檔 ${tag} 已經建置過，略過建置。"
  else
    run gcloud builds submit "${REPO_ROOT}" --tag="${IMAGE_REPO}:${tag}" \
      --machine-type=e2-highcpu-8 --project="${PROJECT}"
  fi
  require_login

  bold "5d. 資料表（migration）"
  local job=culture-bridge-migrate
  if gcloud run jobs describe "${job}" --region="${REGION}" --project="${PROJECT}" >/dev/null 2>&1; then
    run gcloud run jobs update "${job}" --image="${IMAGE_REPO}:${tag}" --region="${REGION}" \
      --project="${PROJECT}"
  else
    run gcloud run jobs create "${job}" --image="${IMAGE_REPO}:${tag}" --region="${REGION}" \
      --project="${PROJECT}" --service-account="${SA}" --set-cloudsql-instances="${conn}" \
      --set-secrets=DATABASE_URL=database-url:latest --command=alembic --args=upgrade,head
  fi
  local first
  read -r -p "  這個資料庫是用第一版 schema 手動建的、而且第一次接 Alembic 嗎？(y/N) " first
  if [[ "${first}" == "y" ]]; then
    run gcloud run jobs execute "${job}" --region="${REGION}" --project="${PROJECT}" \
      --args=stamp,0001_initial_schema --wait
  fi
  run gcloud run jobs execute "${job}" --region="${REGION}" --project="${PROJECT}" --wait

  bold "5e. 部署服務"
  [[ -n "${FIREBASE_WEB_API_KEY:-}" ]] || note "還沒有 Firebase 設定（步驟 4），部署後無法登入。"
  confirm_yes "會部署 culture-bridge 服務並公開網址（依用量計費，min-instances=0 閒置時不收 CPU 費用）。" \
    || { note "已取消"; return 0; }
  run gcloud run deploy culture-bridge --image="${IMAGE_REPO}:${tag}" --region="${REGION}" \
    --project="${PROJECT}" --service-account="${SA}" --add-cloudsql-instances="${conn}" \
    --allow-unauthenticated --memory=512Mi --cpu=1 --min-instances=0 --max-instances=2 \
    --concurrency=40 \
    --set-secrets=DATABASE_URL=database-url:latest,GEMINI_API_KEY=gemini-api-key:latest \
    --update-env-vars="APP_ENV=production,FIREBASE_PROJECT_ID=${PROJECT},FIREBASE_WEB_API_KEY=${FIREBASE_WEB_API_KEY:-},FIREBASE_WEB_APP_ID=${FIREBASE_WEB_APP_ID:-},FIREBASE_AUTH_DOMAIN=${FIREBASE_AUTH_DOMAIN:-},FIREBASE_MESSAGING_SENDER_ID=${FIREBASE_MESSAGING_SENDER_ID:-}"

  SERVICE_URL="$(gcloud run services describe culture-bridge --region="${REGION}" \
    --project="${PROJECT}" --format='value(status.url)' 2>/dev/null || true)"
  save_state
  if [[ -n "${SERVICE_URL}" ]]; then
    note "網址：${SERVICE_URL}"
    add_authorized_domain "${SERVICE_URL#https://}"
    note "檢查：$(curl -fsS "${SERVICE_URL}/health" 2>/dev/null || echo '尚未回應')"
    note "設定：$(curl -fsS "${SERVICE_URL}/api/config" 2>/dev/null || echo '尚未回應')"
  fi

  bold "5f. 第一位管理者"
  note "1. 用 Google 登入網頁版 → 「我的」→「帳號」複製帳號編號"
  note "2. Cloud SQL Studio 執行：UPDATE users SET role='admin' WHERE id='<帳號編號>';"
}

# ---------- 6. monitoring (A-8) ----------

step_monitoring() {
  bold "6. 監控（A-8）"
  [[ -n "${SERVICE_URL:-}" ]] || ask SERVICE_URL "服務網址（https://…）"
  [[ "${SERVICE_URL}" == https://* ]] || die "需要服務網址，請先完成步驟 5（部署）。"
  # /healthz is reserved by Cloud Run and never reaches the app, so check /health.
  run gcloud monitoring uptime create culture-bridge-uptime --project="${PROJECT}" \
    --resource-type=uptime-url \
    --resource-labels="host=${SERVICE_URL#https://},project_id=${PROJECT}" \
    --path=/health --protocol=https --period=5
  note "伺服器錯誤會自動出現在 Error Reporting：https://console.cloud.google.com/errors?project=${PROJECT}"
  note "到 Monitoring → Alerting 為這個 uptime check 建立 Email 通知（主控台約一分鐘）。"
}

# ---------- 7. official procedure drafts (D-8) ----------

step_import() {
  bold "7. 匯入官方流程卡草稿（D-8）"
  note "只建立未發布的草稿與來源；審查者在網頁版後台核對來源、修正後才發布。"
  need_instance
  local conn="${PROJECT}:${REGION}:${INSTANCE}" job=culture-bridge-import image
  SA="culture-bridge-run@${PROJECT}.iam.gserviceaccount.com"
  # Use the image the migration job runs, i.e. the deployed version (step 5).
  image="$(gcloud run jobs describe culture-bridge-migrate --region="${REGION}" \
    --project="${PROJECT}" --format='value(spec.template.spec.template.spec.containers[0].image)' \
    2>/dev/null || true)"
  [[ -n "${image}" ]] || die "找不到 culture-bridge-migrate，請先完成步驟 5（部署）。"
  note "映像檔：${image}"
  if gcloud run jobs describe "${job}" --region="${REGION}" --project="${PROJECT}" >/dev/null 2>&1; then
    run gcloud run jobs update "${job}" --image="${image}" --region="${REGION}" --project="${PROJECT}"
  else
    run gcloud run jobs create "${job}" --image="${image}" --region="${REGION}" \
      --project="${PROJECT}" --service-account="${SA}" --set-cloudsql-instances="${conn}" \
      --set-secrets=DATABASE_URL=database-url:latest \
      --command=python --args=-m,app.official_content
  fi
  run gcloud run jobs execute "${job}" --region="${REGION}" --project="${PROJECT}" --wait
  note "完成後到網頁版「管理 → 流程」審查草稿；說明見 docs/content/d8-official-procedures.md"
}

# ---------- menu ----------

# ---------- 8. automatic deployment from GitHub ----------

GITHUB_REPO="Helen-luv0901/Culture_Bridge"

step_autodeploy() {
  bold "8. 合併到 main 後自動部署（GitHub Actions）"
  note "設定一次就好。GitHub 用短期憑證登入（不產生金鑰檔），只有這個 repo 的 main 能登入，"
  note "權限只有：推映像檔、更新 migration／匯入工作、部署新版本。CI 通過後自動執行 scripts/deploy.sh。"
  local deploy_sa="culture-bridge-deploy@${PROJECT}.iam.gserviceaccount.com"
  local run_sa="culture-bridge-run@${PROJECT}.iam.gserviceaccount.com"
  local number pool=github provider=github
  number="$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)')"
  confirm_yes "會建立部署用服務帳戶 culture-bridge-deploy，並允許 GitHub ${GITHUB_REPO} 的 main 分支用它部署。" \
    || { note "已取消"; return 0; }

  run gcloud services enable iamcredentials.googleapis.com sts.googleapis.com --project="${PROJECT}"
  gcloud iam service-accounts describe "${deploy_sa}" --project="${PROJECT}" >/dev/null 2>&1 \
    || run gcloud iam service-accounts create culture-bridge-deploy --project="${PROJECT}" \
      --display-name="Culture Bridge deploy (GitHub Actions)"
  for role in roles/run.developer roles/artifactregistry.writer; do
    run gcloud projects add-iam-policy-binding "${PROJECT}" --member="serviceAccount:${deploy_sa}" \
      --role="${role}" --condition=None --quiet
  done
  # Deploying a revision or running a job "as" the runtime account needs actAs on that account only.
  run gcloud iam service-accounts add-iam-policy-binding "${run_sa}" --project="${PROJECT}" \
    --member="serviceAccount:${deploy_sa}" --role=roles/iam.serviceAccountUser --quiet

  gcloud iam workload-identity-pools describe "${pool}" --location=global \
    --project="${PROJECT}" >/dev/null 2>&1 \
    || run gcloud iam workload-identity-pools create "${pool}" --location=global \
      --project="${PROJECT}" --display-name="GitHub Actions"
  gcloud iam workload-identity-pools providers describe "${provider}" --location=global \
    --workload-identity-pool="${pool}" --project="${PROJECT}" >/dev/null 2>&1 \
    || run gcloud iam workload-identity-pools providers create-oidc "${provider}" \
      --location=global --workload-identity-pool="${pool}" --project="${PROJECT}" \
      --display-name="GitHub Culture_Bridge" \
      --issuer-uri=https://token.actions.githubusercontent.com \
      --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
      --attribute-condition="assertion.repository=='${GITHUB_REPO}' && assertion.ref=='refs/heads/main'"
  run gcloud iam service-accounts add-iam-policy-binding "${deploy_sa}" --project="${PROJECT}" \
    --role=roles/iam.workloadIdentityUser \
    --member="principalSet://iam.googleapis.com/projects/${number}/locations/global/workloadIdentityPools/${pool}/attribute.repository/${GITHUB_REPO}"

  bold "最後一步：在 GitHub 打開自動部署開關"
  note "1. 打開 https://github.com/${GITHUB_REPO}/settings/variables/actions"
  note "2. 按 New repository variable，Name 填 AUTO_DEPLOY，Value 填 true，按 Add variable"
  note "之後每次合併到 main、CI 通過，就會自動部署；進度在 GitHub 的 Actions → Deploy。"
  note "要暫停：把 AUTO_DEPLOY 改成 false。要完全撤銷：刪除服務帳戶 culture-bridge-deploy。"
  [[ "${number}" == "689086323045" ]] \
    || note "注意：專案編號是 ${number}，請把 .github/workflows/deploy.yml 裡的 689086323045 改成這個。"
}

# ---------- 10. backups and point-in-time recovery ----------

step_backups() {
  bold "10. 備份與時間點還原（PITR）"
  note "每日備份只能回到備份當下；時間點還原可以回到過去 7 天內的任一秒（例如誤刪資料前一刻）。"
  ask INSTANCE "執行個體名稱" "${INSTANCE:-culturebridge-db}"
  save_state
  gcloud sql instances describe "${INSTANCE}" --project="${PROJECT}" \
    --format='table(settings.backupConfiguration.enabled:label=每日備份,settings.backupConfiguration.pointInTimeRecoveryEnabled:label=時間點還原,settings.backupConfiguration.transactionLogRetentionDays:label=保留天數)'
  confirm_yes "會開啟每日備份與時間點還原（保留 7 天交易紀錄，依紀錄大小多一點儲存費用；執行個體可能短暫重新啟動，請選離峰時間）。" \
    || { note "已取消"; return 0; }
  run gcloud sql instances patch "${INSTANCE}" --project="${PROJECT}" \
    --backup-start-time=18:00 --enable-point-in-time-recovery --retained-transaction-log-days=7
  note "怎麼還原：docs/runbooks/rollback-and-restore.md"
}

menu() {
  cat <<EOF

Culture Bridge — Google Cloud 設定（專案 ${PROJECT}，區域 ${REGION}）$([[ "${DRY_RUN}" == "1" ]] && echo "  [DRY_RUN]")
  0) 專案與 API（第一次先做）
  1) 費用警報（A-1）
  2) 資料庫搬遷與帳號、備份（A-3、A-2）— 期限 11/10
  3) Gemini 金鑰（A-5）
  4) Firebase 登入
  5) 部署網頁版與後端（A-7）
  6) 監控（A-8）
  7) 匯入官方流程卡草稿（D-8，部署後）
  8) 合併到 main 後自動部署（設定一次）
  9) 刪除舊的試用執行個體（確認新資料庫正常後）
  10) 備份與時間點還原（PITR）
  q) 離開
EOF
}

main() {
  command -v gcloud >/dev/null || die "找不到 gcloud；請在 Google Cloud Shell 執行。"
  if [[ $# -gt 0 ]]; then
    local step
    # Later steps build on earlier ones (7 needs 5's image), so stop at the first failure.
    for step in "$@"; do
      do_step "${step}" || { note "後面的步驟沒有執行。"; return 1; }
    done
    return
  fi
  while true; do
    menu
    read -r -p "選擇: " choice || break
    [[ "${choice}" == "q" ]] && break
    do_step "${choice}" || true
  done
}

# Each step runs in a subshell with errexit on, so the first failing command stops that step
# (errexit is ignored in `||` contexts). Values it saved are reloaded afterwards.
do_step() {
  local rc
  set +e
  (set -e; require_login; dispatch "$1")
  rc=$?
  set -e
  # shellcheck disable=SC1090
  [[ -f "${STATE}" ]] && source "${STATE}"
  [[ ${rc} -eq 0 ]] || note "這一步沒有完成，可以修正後重新執行。"
  return "${rc}"
}

dispatch() {
  case "$1" in
    0) step_project ;;
    1) step_budget ;;
    2) step_database ;;
    3) step_gemini ;;
    4) step_firebase ;;
    5) step_deploy ;;
    6) step_monitoring ;;
    7) step_import ;;
    8) step_autodeploy ;;
    9) step_cleanup_old ;;
    10) step_backups ;;
    *) note "沒有這個選項：$1" ;;
  esac
}

main "$@"
