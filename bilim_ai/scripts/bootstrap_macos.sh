#!/usr/bin/env bash
set -euo pipefail

# One-time macOS project bootstrap

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
cd "$ROOT_DIR"

echo "[i] Enabling macOS desktop..."
flutter config --enable-macos-desktop || true

echo "[i] Fetching pub dependencies..."
flutter pub get

echo "[i] Done. To run: scripts/run_macos.sh --key <YOUR_GEMINI_API_KEY>"


