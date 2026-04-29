#!/usr/bin/env bash
set -euo pipefail

# クラウド環境のみセットアップを実行する
if [[ -z "${CI:-}" && -z "${CODESPACES:-}" && -z "${GITHUB_ACTIONS:-}" && -z "${CODEX_SANDBOX:-}" ]]; then
  echo "ローカル環境のためスキップします。"
  exit 0
fi

# .NET 10 SDK が無い場合のみ導入
if ! command -v dotnet >/dev/null 2>&1 || ! dotnet --list-sdks | grep -q '^10\.'; then
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  bash /tmp/dotnet-install.sh --channel 10.0 --install-dir "$HOME/.dotnet"
  export PATH="$HOME/.dotnet:$PATH"
fi

dotnet --info
