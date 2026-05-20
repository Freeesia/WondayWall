#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_PROJECT_DIR="$PROJECT_ROOT/WondayWall.Android"
ANDROID_COMPILE_SDK_PACKAGE="platforms;android-37.0"
ANDROID_BUILD_TOOLS_PACKAGE="build-tools;37.0.0"
ANDROID_GRADLE_VERSION="9.5.1"
ANDROID_GRADLE_HOME="$HOME/.gradle/codex/gradle-$ANDROID_GRADLE_VERSION"

# クラウド環境のみセットアップを実行する
if [[ -z "${CI:-}" && -z "${CODESPACES:-}" && -z "${GITHUB_ACTIONS:-}" && -z "${CODEX_SANDBOX:-}" ]]; then
  echo "ローカル環境のためスキップします。"
  exit 0
fi

download_file() {
  local url="$1"
  local output="$2"
  curl -fsSL "$url" -o "$output"
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual

  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    actual="$(sha256sum "$file" | awk '{print $1}')"
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "SHA-256 が一致しません: $file" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

run_sdkmanager_with_yes() {
  local sdkmanager="$1"
  shift

  set +o pipefail
  yes | "$sdkmanager" "$@"
  local sdkmanager_status="${PIPESTATUS[1]}"
  set -o pipefail

  if [[ "$sdkmanager_status" -ne 0 ]]; then
    exit "$sdkmanager_status"
  fi
}

resolve_android_sdk_root() {
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    echo "$ANDROID_SDK_ROOT"
  elif [[ -n "${ANDROID_HOME:-}" ]]; then
    echo "$ANDROID_HOME"
  else
    echo "$HOME/Library/Android/sdk"
  fi
}

install_android_command_line_tools() {
  local sdk_root="$1"
  local sdkmanager="$sdk_root/cmdline-tools/latest/bin/sdkmanager"

  if [[ -x "$sdkmanager" ]]; then
    return
  fi

  local tools_url="https://dl.google.com/android/repository/commandlinetools-mac-14742923_latest.zip"
  local tools_sha256="ed304c5ede3718541e4f978e4ae870a4d853db74af6c16d920588d48523b9dee"

  local temp_dir
  temp_dir="$(mktemp -d)"

  echo "Android command-line tools を導入します。"
  download_file "$tools_url" "$temp_dir/commandlinetools.zip"
  verify_sha256 "$temp_dir/commandlinetools.zip" "$tools_sha256"

  mkdir -p "$sdk_root/cmdline-tools"
  unzip -q "$temp_dir/commandlinetools.zip" -d "$temp_dir"
  rm -rf "$sdk_root/cmdline-tools/latest"
  mkdir -p "$sdk_root/cmdline-tools/latest"
  mv "$temp_dir/cmdline-tools/"* "$sdk_root/cmdline-tools/latest/"
  rm -rf "$temp_dir"
}

setup_android_sdk() {
  local sdk_root
  sdk_root="$(resolve_android_sdk_root)"

  mkdir -p "$sdk_root"
  export ANDROID_SDK_ROOT="$sdk_root"
  export ANDROID_HOME="$sdk_root"
  export PATH="$sdk_root/cmdline-tools/latest/bin:$sdk_root/platform-tools:$PATH"

  install_android_command_line_tools "$sdk_root"

  local sdkmanager="$sdk_root/cmdline-tools/latest/bin/sdkmanager"
  run_sdkmanager_with_yes "$sdkmanager" --sdk_root="$sdk_root" --licenses >/dev/null
  run_sdkmanager_with_yes "$sdkmanager" --sdk_root="$sdk_root" \
    "platform-tools" \
    "$ANDROID_COMPILE_SDK_PACKAGE" \
    "$ANDROID_BUILD_TOOLS_PACKAGE"
  run_sdkmanager_with_yes "$sdkmanager" --sdk_root="$sdk_root" --licenses >/dev/null

  mkdir -p "$ANDROID_PROJECT_DIR"
  printf 'sdk.dir=%s\n' "$sdk_root" > "$ANDROID_PROJECT_DIR/local.properties"
}

setup_android_gradle() {
  local gradle_bin="$ANDROID_GRADLE_HOME/bin/gradle"

  if [[ -x "$gradle_bin" ]]; then
    return
  fi

  local gradle_url="https://services.gradle.org/distributions/gradle-$ANDROID_GRADLE_VERSION-bin.zip"
  local temp_dir
  temp_dir="$(mktemp -d)"

  echo "Gradle $ANDROID_GRADLE_VERSION を導入します。"
  download_file "$gradle_url" "$temp_dir/gradle.zip"
  mkdir -p "$(dirname "$ANDROID_GRADLE_HOME")"
  rm -rf "$ANDROID_GRADLE_HOME"
  unzip -q "$temp_dir/gradle.zip" -d "$(dirname "$ANDROID_GRADLE_HOME")"
  rm -rf "$temp_dir"
}

# .NET 10 SDK が無い場合のみ導入
if ! command -v dotnet >/dev/null 2>&1 || ! dotnet --list-sdks | grep -q '^10\.'; then
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  bash /tmp/dotnet-install.sh --channel 10.0 --install-dir "$HOME/.dotnet"
  export PATH="$HOME/.dotnet:$PATH"
fi

dotnet --info

setup_android_sdk
setup_android_gradle

echo "Android Debug ビルド環境のセットアップが完了しました。"
