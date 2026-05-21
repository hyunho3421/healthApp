#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REQUEST="${1:-APK 빌드/업로드}"
CHANGES="${2:-앱 변경사항 반영}"
DRIVE_DIR="G:\\내 드라이브\\dev"
RELEASE_SRC="build/app/outputs/apk/release/app-release.apk"
DEBUG_SRC="build/app/outputs/apk/debug/app-debug.apk"
RELEASE_NAME="muscle_growth_diary-release.apk"
DEBUG_NAME="muscle_growth_diary-debug.apk"
REPORT_PATH="build/apk-completion-report.txt"

export PATH="/home/kimnx/.local/dev/flutter/bin:/home/kimnx/.local/dev/jdk-17/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-/home/kimnx/.local/dev/jdk-17}"

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "[error] missing file: $1" >&2
    exit 1
  fi
}

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

zip_ok() {
  python3 - "$1" <<'PY'
import sys, zipfile
p = sys.argv[1]
if not zipfile.is_zipfile(p):
    raise SystemExit(1)
PY
}

printf '[1/6] flutter analyze\n'
flutter analyze

printf '[2/6] flutter build apk --release\n'
flutter build apk --release

printf '[3/6] flutter build apk --debug\n'
flutter build apk --debug

printf '[4/6] verify local APKs\n'
require_file "$RELEASE_SRC"
require_file "$DEBUG_SRC"
zip_ok "$RELEASE_SRC"
zip_ok "$DEBUG_SRC"
release_size=$(stat -c '%s' "$RELEASE_SRC")
debug_size=$(stat -c '%s' "$DEBUG_SRC")
release_hash=$(sha256_of "$RELEASE_SRC")
debug_hash=$(sha256_of "$DEBUG_SRC")
release_mtime=$(date -d "@$(stat -c '%Y' "$RELEASE_SRC")" '+%Y-%m-%d %H:%M:%S')
debug_mtime=$(date -d "@$(stat -c '%Y' "$DEBUG_SRC")" '+%Y-%m-%d %H:%M:%S')

printf '[5/6] copy APKs to Google Drive\n'
PS="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
if [[ ! -x "$PS" ]]; then
  echo "[error] PowerShell not found: $PS" >&2
  exit 1
fi
release_win=$(wslpath -w "$ROOT/$RELEASE_SRC")
debug_win=$(wslpath -w "$ROOT/$DEBUG_SRC")
copy_output=$("$PS" -NoProfile -Command "
  Copy-Item -LiteralPath '$release_win' -Destination '$DRIVE_DIR\\$RELEASE_NAME' -Force;
  Copy-Item -LiteralPath '$debug_win' -Destination '$DRIVE_DIR\\$DEBUG_NAME' -Force;
  Get-Item '$DRIVE_DIR\\$RELEASE_NAME','$DRIVE_DIR\\$DEBUG_NAME' | ForEach-Object { Write-Output (\$_.Name + '|' + \$_.Length + '|' + \$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) }
")
printf '%s\n' "$copy_output"

printf '[6/6] generate completion report\n'
mkdir -p build
cat > "$REPORT_PATH" <<EOF_REPORT
완료됐습니다.

요청내용:
- $REQUEST

반영:
- $CHANGES

검증:
- \`flutter analyze\` 통과
- release/debug APK 빌드 성공
- APK zip 무결성 OK
- release APK: ${release_size} bytes, sha256 ${release_hash}, 생성 ${release_mtime}
- debug APK: ${debug_size} bytes, sha256 ${debug_hash}, 생성 ${debug_mtime}

업로드:
\`$DRIVE_DIR\`
- \`$RELEASE_NAME\`
- \`$DEBUG_NAME\`
EOF_REPORT

printf '\n===== COMPLETION REPORT =====\n'
cat "$REPORT_PATH"
printf '\n===== END REPORT =====\n'
printf '[ok] report saved: %s\n' "$REPORT_PATH"
