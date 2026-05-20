#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_PROJECT_DIR="$PROJECT_ROOT/WondayWall.Android"
ANDROID_GRADLE_VERSION="9.5.1"
SETUP_GRADLE="$HOME/.gradle/codex/gradle-$ANDROID_GRADLE_VERSION/bin/gradle"

if [[ -x "$SETUP_GRADLE" ]]; then
  GRADLE_BIN="$SETUP_GRADLE"
elif command -v gradle >/dev/null 2>&1; then
  GRADLE_BIN="$(command -v gradle)"
else
  echo "Gradle が見つかりません。先に ./scripts/setup-cloud-build.sh を実行してください。" >&2
  exit 1
fi

cd "$ANDROID_PROJECT_DIR"
"$GRADLE_BIN" :app:assembleDebug --no-daemon
