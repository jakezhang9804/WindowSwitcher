#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/Scripts/test-appswitcherkit.sh"
"$ROOT_DIR/Scripts/test-appswitcherkit.sh" "$ROOT_DIR"
