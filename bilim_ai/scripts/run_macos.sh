#!/usr/bin/env bash
set -euo pipefail

# Simple runner for macOS with --dart-define API key support

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
cd "$ROOT_DIR"

KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key)
      KEY="$2"; shift 2 ;;
    *)
      echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Try env var
if [[ -z "$KEY" && -n "${BILIM_GEMINI_API_KEY:-}" ]]; then
  KEY="$BILIM_GEMINI_API_KEY"
fi

# Try .env.local
if [[ -z "$KEY" && -f .env.local ]]; then
  KEY_LINE=$(grep -E '^BILIM_GEMINI_API_KEY=' .env.local || true)
  if [[ -n "$KEY_LINE" ]]; then
    KEY="${KEY_LINE#BILIM_GEMINI_API_KEY=}"
  fi
fi

# Если ключ не найден, продолжим запуск — приложение возьмёт ключ из lib/api_key.dart

flutter config --enable-macos-desktop >/dev/null 2>&1 || true
flutter pub get

if [[ -n "$KEY" ]]; then
  exec flutter run -d macos --debug --dart-define=BILIM_GEMINI_API_KEY="$KEY"
else
  exec flutter run -d macos --debug
fi


