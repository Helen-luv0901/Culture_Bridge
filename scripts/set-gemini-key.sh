#!/usr/bin/env bash
# Culture Bridge — switch the live service to another Gemini API key (for example a free one).
#
#   bash scripts/set-gemini-key.sh
#
# 1. asks for the key without showing it
# 2. finds a text model this key may really call (a free key cannot call every model) and checks
#    the embedding model used by semantic search
# 3. only when the text model works and you answer y: stores the key as a new version of the
#    gemini-api-key secret, sets GEMINI_MODEL and starts a new revision so it takes effect.
# The key is kept in memory and sent only to Google and Secret Manager; it is never printed.
# Going back: run this again with the old key, or roll back the revision in Cloud Run.

set -uo pipefail

PROJECT="${PROJECT:-culture-bridge-511321}"
REGION="${REGION:-asia-east1}"
SERVICE=culture-bridge
SECRET=gemini-api-key
API=https://generativelanguage.googleapis.com/v1beta
EMBEDDING_MODEL="${EMBEDDING_MODEL:-gemini-embedding-001}"
BODY="$(mktemp)"
trap 'rm -f "${BODY}"' EXIT

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32mOK\033[0m  %s\n' "$*"; }
bad() { printf '  \033[31mNG\033[0m  %s\n' "$*"; }
note() { printf '      %s\n' "$*"; }
die() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# call METHOD PATH [JSON] → HTTP status; the response body is in ${BODY}.
call() {
  local args=()
  [[ -n "${3:-}" ]] && args=(-d "$3")
  curl -sS -o "${BODY}" -w '%{http_code}' -X "$1" "${API}/$2" \
    -H "x-goog-api-key: ${KEY}" -H 'Content-Type: application/json' "${args[@]}" 2>/dev/null
}
error_of() { python3 -c 'import json,sys
try: e=json.load(open(sys.argv[1]))["error"]; print(e.get("status",""), e.get("message","")[:200])
except Exception: print("(no error message)")' "${BODY}"; }

command -v gcloud >/dev/null || die "找不到 gcloud；請在 Google Cloud Shell 執行。"
[[ -n "$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)" ]] \
  || die "目前沒有登入的 Google 帳號。執行 gcloud config set account <你的 Google 帳號> 後再試一次。"

bold "1. 輸入新的 Gemini 金鑰（畫面不會顯示，貼上後按 Enter）"
read -rs -p "  金鑰: " KEY
printf '\n'
KEY="$(printf '%s' "${KEY}" | tr -d '[:space:]')"
[[ -n "${KEY}" ]] || die "沒有輸入金鑰。"

status="$(call GET 'models?pageSize=200')"
[[ "${status}" == "200" ]] || die "這把金鑰不能用：HTTP ${status} $(error_of)"
ok "金鑰有效（長度 ${#KEY}）"

bold "2. 找這把金鑰真的能用的模型"
current="$(gcloud run services describe "${SERVICE}" --region="${REGION}" --project="${PROJECT}" \
  --format=json 2>/dev/null | python3 -c 'import json,sys
env=json.load(sys.stdin)["spec"]["template"]["spec"]["containers"][0].get("env",[])
print(next((e.get("value","") for e in env if e["name"]=="GEMINI_MODEL"),""))' 2>/dev/null || true)"
# The model asked for (MODEL=…), the one in use, then this key's stable flash models, newest first
# (full flash before flash-lite; no preview, image, audio or live variants).
mapfile -t candidates < <(python3 - "${BODY}" "${MODEL:-}" "${current}" <<'EOF'
import json, re, sys
models = json.load(open(sys.argv[1])).get("models", [])
names = [m["name"].split("/", 1)[1] for m in models
         if "generateContent" in m.get("supportedGenerationMethods", [])]
stable = [n for n in names if re.fullmatch(r"gemini-[\d.]+-flash(-lite)?", n)]
version = lambda n: tuple(int(x) for x in re.findall(r"\d+", n))
stable.sort(key=lambda n: ("lite" in n, tuple(-v for v in version(n))))
seen = []
for n in [sys.argv[2], sys.argv[3], "gemini-3.8-flash", *stable]:
    if n and n in names and n not in seen:
        seen.append(n)
print("\n".join(seen[:6]))
EOF
)
[[ ${#candidates[@]} -gt 0 ]] || die "這把金鑰沒有可用的 flash 模型。"

summary='{"contents":[{"parts":[{"text":"用一句話整理：第一次去健保卡櫃台，不知道要帶什麼。"}]}],
"generationConfig":{"temperature":0.2,"responseMimeType":"application/json",
"responseJsonSchema":{"type":"object","properties":{"situation":{"type":"string"}},"required":["situation"]}}}'
model=""
for candidate in "${candidates[@]}"; do
  status="$(call POST "models/${candidate}:generateContent" "${summary}")"
  if [[ "${status}" == "200" ]]; then
    ok "${candidate} 可以用"; model="${candidate}"; break
  fi
  bad "${candidate}：HTTP ${status} $(error_of)"
done
[[ -n "${model}" ]] || die "這把金鑰目前沒有能產生文字的模型，網站沒有變更。免費金鑰若出現 429，可能是今天的免費額度用完，明天再試。"

status="$(call POST "models/${EMBEDDING_MODEL}:embedContent" '{"content":{"parts":[{"text":"居留證"}]}}')"
if [[ "${status}" == "200" ]]; then
  ok "語意搜尋（${EMBEDDING_MODEL}）可以用"
else
  bad "語意搜尋（${EMBEDDING_MODEL}）：HTTP ${status} $(error_of)"
  note "換過去後 AI 整理和助理可以用，但搜尋只會用關鍵字比對。"
fi

bold "3. 換到網站上"
note "會把這把金鑰存成 ${SECRET} 的新版本，模型設成 ${model}，並重新啟動服務（約 1 分鐘，不需要重新建置）。"
read -r -p "  要換嗎？(y/N) " answer
[[ "${answer}" == "y" ]] || { note "已取消，網站沒有變更。"; exit 0; }

version="$(printf '%s' "${KEY}" | gcloud secrets versions add "${SECRET}" --project="${PROJECT}" \
  --data-file=- --format='value(name)' 2>/dev/null)" || die "存不進 Secret Manager。"
unset KEY
version="${version##*/}"
ok "已存成 ${SECRET} 第 ${version} 版"

# GEMINI_KEY_VERSION only forces a new revision, which reads the latest secret version.
gcloud run services update "${SERVICE}" --region="${REGION}" --project="${PROJECT}" --quiet \
  --update-env-vars="GEMINI_MODEL=${model},GEMINI_KEY_VERSION=${version}" \
  || die "服務更新失敗（金鑰已存好）。修正後重新執行這個指令即可。"
ok "服務已更新"

bold "完成。用 bash scripts/check-ai.sh 再檢查一次；第 4、5 步顯示 OK 就好了。"
