#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$PATH"
cd "$PROJECT_ROOT/web"
exec pnpm dev --hostname "${WEB_HOST:-127.0.0.1}" --port "${WEB_PORT:-3000}"
