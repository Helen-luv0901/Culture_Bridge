#!/usr/bin/env bash
# Culture Bridge — check every link the AI features depend on, read-only.
#
#   bash scripts/check-ai.sh
#
# 1. which model the live service uses   2. whether the key in Secret Manager works
# 3. which Gemini models this key may call 4. a real JSON summary call with that model
# 5. an embedding call (semantic search)   6. the latest AI errors in the service logs
# The key is read into memory and sent only to Google; it is never printed.

set -uo pipefail

PROJECT="${PROJECT:-culture-bridge-511321}"
REGION="${REGION:-asia-east1}"
SERVICE=culture-bridge
API=https://generativelanguage.googleapis.com/v1beta
EMBEDDING_MODEL="${EMBEDDING_MODEL:-gemini-embedding-001}"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32mOK\033[0m  %s\n' "$*"; }
bad() { printf '  \033[31mNG\033[0m  %s\n' "$*"; }
note() { printf '      %s\n' "$*"; }

# POST/GET to the Gemini API; prints "<http status> <body>".
call() {
  local method="$1" path="$2" body="${3:-}" args=()
  [[ -n "${body}" ]] && args=(-d "${body}")
  curl -sS -o /tmp/cb-ai-body -w '%{http_code}' -X "${method}" "${API}/${path}" \
    -H "x-goog-api-key: ${KEY}" -H 'Content-Type: application/json' "${args[@]}" 2>/dev/null
  printf ' '
  cat /tmp/cb-ai-body 2>/dev/null
}
error_of() { python3 -c 'import json,sys
try: e=json.loads(sys.stdin.read().split(" ",1)[1])["error"]; print(e.get("status",""), e.get("message","")[:300])
except Exception: print("(no error message)")'; }

bold "1. 網站用的模型"
env_model="$(gcloud run services describe "${SERVICE}" --region="${REGION}" --project="${PROJECT}" \
  --format=json 2>/dev/null | python3 -c 'import json,sys
env=json.load(sys.stdin)["spec"]["template"]["spec"]["containers"][0].get("env",[])
print(next((e.get("value","") for e in env if e["name"]=="GEMINI_MODEL"),""))' 2>/dev/null || true)"
image="$(gcloud run services describe "${SERVICE}" --region="${REGION}" --project="${PROJECT}" \
  --format='value(spec.template.spec.containers[0].image)' 2>/dev/null)"
code_default="$(git -C "$(dirname "$0")/.." show "${image##*:}:backend/app/core/config.py" 2>/dev/null \
  | sed -n 's/.*GEMINI_MODEL", "\([^"]*\)".*/\1/p')"
MODEL="${env_model:-${code_default:-gemini-3.8-flash}}"
# Backup models for when MODEL's free quota is used up (GEMINI_FALLBACK_MODELS, comma-separated).
env_fallbacks="$(gcloud run services describe "${SERVICE}" --region="${REGION}" --project="${PROJECT}" \
  --format=json 2>/dev/null | python3 -c 'import json,sys
env=json.load(sys.stdin)["spec"]["template"]["spec"]["containers"][0].get("env",[])
print(next((e.get("value","") for e in env if e["name"]=="GEMINI_FALLBACK_MODELS"),""))' 2>/dev/null || true)"
code_fallbacks="$(git -C "$(dirname "$0")/.." show "${image##*:}:backend/app/core/config.py" 2>/dev/null \
  | sed -n 's/.*GEMINI_FALLBACK_MODELS", "\([^"]*\)".*/\1/p')"
FALLBACKS="${env_fallbacks:-${code_fallbacks}}"
note "線上版本：${image##*:}"
note "模型：${MODEL}$([[ -n "${env_model}" ]] && echo '（服務的 GEMINI_MODEL 設定）' || echo '（程式預設值）')"
note "備用模型：${FALLBACKS:-（沒有）}"

bold "2. 金鑰"
if ! KEY="$(gcloud secrets versions access latest --secret=gemini-api-key --project="${PROJECT}" 2>/dev/null)" \
  || [[ -z "${KEY}" ]]; then
  bad "讀不到 Secret Manager 的 gemini-api-key"; exit 1
fi
ok "已從 Secret Manager 讀到（長度 ${#KEY}，不顯示內容）"
result="$(call GET 'models?pageSize=200')"
if [[ "${result%% *}" != "200" ]]; then
  bad "金鑰不能用：HTTP ${result%% *} $(error_of <<<"${result}")"; exit 1
fi
ok "金鑰有效"

bold "3. 這把金鑰可以用的模型（節錄）"
MODELS_JSON="${result#* }" python3 - "${MODEL}" "${EMBEDDING_MODEL}" <<'EOF'
import json, os, sys
model, embedding = sys.argv[1], sys.argv[2]
models = json.loads(os.environ["MODELS_JSON"]).get("models", [])
names = {m["name"].split("/", 1)[1]: m.get("supportedGenerationMethods", []) for m in models}
gen = sorted(n for n, ms in names.items() if "generateContent" in ms and "flash" in n)
emb = sorted(n for n, ms in names.items() if "embedContent" in ms)
print("      可產生文字的 flash 模型：", ", ".join(gen[-8:]) or "（沒有）")
print("      可做 embedding 的模型：", ", ".join(emb) or "（沒有）")
print("      " + ("OK  " if model in names else "NG  ") + f"{model} {'在' if model in names else '不在'}清單中")
print("      " + ("OK  " if embedding in names else "NG  ") + f"{embedding} {'在' if embedding in names else '不在'}清單中")
EOF

bold "4. 用 ${MODEL} 實際整理一句話（和「AI 整理」同樣的 JSON 格式）"
body='{"contents":[{"parts":[{"text":"用一句話整理：第一次去健保卡櫃台，不知道要帶什麼。"}]}],
"generationConfig":{"temperature":0.2,"responseMimeType":"application/json",
"responseJsonSchema":{"type":"object","properties":{"situation":{"type":"string"}},"required":["situation"]}}}'
result="$(call POST "models/${MODEL}:generateContent" "${body}")"
if [[ "${result%% *}" == "200" ]]; then
  ok "成功：$(python3 -c 'import json,sys; r=json.loads(sys.stdin.read().split(" ",1)[1]); print(r["candidates"][0]["content"]["parts"][0]["text"][:120])' <<<"${result}" 2>/dev/null)"
else
  bad "失敗：HTTP ${result%% *} $(error_of <<<"${result}")"
fi

for fallback in ${FALLBACKS//,/ }; do
  bold "4b. 備用模型 ${fallback}（${MODEL} 額度用完時改用）"
  result="$(call POST "models/${fallback}:generateContent" "${body}")"
  if [[ "${result%% *}" == "200" ]]; then ok "可以用"; else bad "失敗：HTTP ${result%% *} $(error_of <<<"${result}")"; fi
done

bold "5. 語意搜尋用的 embedding（${EMBEDDING_MODEL}）"
result="$(call POST "models/${EMBEDDING_MODEL}:embedContent" '{"content":{"parts":[{"text":"居留證"}]}}')"
if [[ "${result%% *}" == "200" ]]; then ok "成功"; else bad "失敗：HTTP ${result%% *} $(error_of <<<"${result}")"; fi
unset KEY

bold "6. 最近的 AI 錯誤紀錄（最新在上）"
gcloud logging read "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${SERVICE}\" AND (textPayload:\"Gemini\" OR textPayload:\"GEMINI\" OR textPayload:\"fallback\" OR textPayload:\"Indexing\")" \
  --project="${PROJECT}" --limit=6 --freshness=2d --format='value(timestamp,resource.labels.revision_name,textPayload)' \
  | cut -c1-400
rm -f /tmp/cb-ai-body
