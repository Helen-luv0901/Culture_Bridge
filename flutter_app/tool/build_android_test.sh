#!/usr/bin/env bash
# Builds an Android APK for trying the app on your own phone (signed with this computer's
# debug key, so it is NOT the Play Store build).
#
#   bash tool/build_android_test.sh
#
# Needs android/app/google-services.json from the Firebase console (Project settings → your
# Android app). Firebase settings are read from it and passed as --dart-define, so the app
# signs in with the Android app's own id. The APK ends up in build/app/outputs/flutter-apk/.
set -euo pipefail

cd "$(dirname "$0")/.."
config=android/app/google-services.json
package=com.culturebridge.culture_bridge
flutter=${FLUTTER:-flutter}
command -v "$flutter" >/dev/null 2>&1 || flutter=/c/flutter/bin/flutter

if [[ ! -f "$config" ]]; then
  echo "找不到 $config：請先在 Firebase 主控台註冊 Android App（$package）並下載它。" >&2
  exit 1
fi

# One --dart-define per Firebase setting, from the client entry for our package.
mapfile -t defines < <(python - "$config" "$package" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
project = data["project_info"]
client = next(
    c for c in data["client"]
    if c["client_info"]["android_client_info"]["package_name"] == sys.argv[2]
)
values = {
    "FIREBASE_API_KEY": client["api_key"][0]["current_key"],
    "FIREBASE_ANDROID_APP_ID": client["client_info"]["mobilesdk_app_id"],
    "FIREBASE_PROJECT_ID": project["project_id"],
    "FIREBASE_MESSAGING_SENDER_ID": project["project_number"],
    "FIREBASE_STORAGE_BUCKET": project.get("storage_bucket", ""),
    "FIREBASE_AUTH_DOMAIN": f'{project["project_id"]}.firebaseapp.com',
}
for key, value in values.items():
    if value:
        print(f"--dart-define={key}={value}")
PY
)

API_BASE_URL=${API_BASE_URL:-https://culture-bridge-z7gcp33vjq-de.a.run.app}
echo "建置測試用 APK（伺服器：$API_BASE_URL）…"
CB_ALLOW_DEBUG_SIGNING=1 "$flutter" build apk --release \
  --dart-define=API_BASE_URL="$API_BASE_URL" "${defines[@]}"
echo "完成：build/app/outputs/flutter-apk/app-release.apk"
