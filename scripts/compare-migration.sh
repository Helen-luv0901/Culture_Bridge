#!/usr/bin/env bash
# Compare row counts after the A-3 database migration (read-only).
#   old = the export file in Cloud Storage (exactly what the trial instance held)
#   new = the new Cloud SQL instance, using the postgres password stored in database-url
# Run in Cloud Shell after `bash scripts/gcp-setup.sh 2`:  bash scripts/compare-migration.sh

set -euo pipefail

STATE="${HOME}/.culture-bridge-setup.env"
# shellcheck disable=SC1090
[[ -f "${STATE}" ]] && source "${STATE}"
PROJECT="${PROJECT:?先執行 scripts/gcp-setup.sh 步驟 0}"
REGION="${REGION:-asia-east1}"
INSTANCE="${INSTANCE:?先執行 scripts/gcp-setup.sh 步驟 2}"
DB="${DB:-culturebridge}"
BUCKET="${BUCKET:-gs://${PROJECT}-sql-migration}"
PORT="${PORT:-9480}"

tmp="$(mktemp -d)"
proxy=""
cleanup() {
  [[ -n "${proxy}" ]] && kill "${proxy}" 2>/dev/null
  rm -rf "${tmp}"
}
trap cleanup EXIT

echo "讀取匯出檔 ${BUCKET}/${DB}.sql.gz …"
gcloud storage cat "${BUCKET}/${DB}.sql.gz" | gunzip \
  | awk '/^COPY /{t=$2; n=0; inside=1; next} inside && /^\\\.$/{print t, n; inside=0; next} inside{n++}' \
  | sort >"${tmp}/old"

echo "連線新資料庫 ${INSTANCE} …"
password="$(gcloud secrets versions access latest --secret=database-url --project="${PROJECT}" \
  | sed -E 's#^[^:]+://postgres:([^@]*)@.*#\1#')"
cloud-sql-proxy "${PROJECT}:${REGION}:${INSTANCE}" --port "${PORT}" >"${tmp}/proxy.log" 2>&1 &
proxy=$!
for _ in $(seq 1 20); do
  (echo >"/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null && break
  sleep 1
done
PGPASSWORD="${password}" psql -X -q -A -t -F ' ' -v ON_ERROR_STOP=1 \
  "host=127.0.0.1 port=${PORT} user=postgres dbname=${DB}" <<'SQL' | sort >"${tmp}/new"
SELECT table_schema || '.' || table_name,
       (xpath('/row/c/text()', query_to_xml(
          format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
SQL

echo
printf '%-36s %10s %10s  %s\n' "資料表" "匯出檔" "新資料庫" "結果"
join -a1 -a2 -e '-' -o 0,1.2,2.2 "${tmp}/old" "${tmp}/new" \
  | awk '{ ok = ($2 == $3); bad += !ok
           printf "%-36s %10s %10s  %s\n", $1, $2, $3, (ok ? "OK" : "不一致") }
         END { print ""; print (bad ? "有 " bad " 張表不一致，先不要刪除舊執行個體。" : "全部一致。") }'
