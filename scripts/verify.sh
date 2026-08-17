#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$HOME/.local/bin:$PATH"

cd "$PROJECT_ROOT"
bash -n scripts/*.sh
node --check scripts/verify-bsc-draft.mjs
node --check scripts/audit-core-deployment.mjs
node --check scripts/prepare-source-verification.mjs
python3 model/train_sparse.py
python3 model/benchmark_sparse.py
python3 model/release_acceptance_v4.py --report-only
python3 model/release_acceptance_v5.py

cd contracts
forge fmt --check
forge test
forge build --sizes
forge lint --severity high --severity med

cd ..
bash scripts/preflight-bsc-local.sh >/dev/null
node scripts/verify-bsc-draft.mjs
VERIFY_SOURCE_DIR="$(mktemp -d /tmp/tinyai-source-verify.XXXXXX)"
trap 'rm -rf "$VERIFY_SOURCE_DIR"' EXIT
FORGE="$HOME/.foundry/bin/forge" node scripts/prepare-source-verification.mjs --output "$VERIFY_SOURCE_DIR" >/dev/null
test -s "$VERIFY_SOURCE_DIR/model-card.constructor-args.txt"
test -s "$VERIFY_SOURCE_DIR/chat.constructor-args.txt"
test -s "$VERIFY_SOURCE_DIR/model-card.standard-input.json"
test -s "$VERIFY_SOURCE_DIR/chat.standard-input.json"

cd web
node --check scripts/paid-e2e.mjs
node --check scripts/verify-paid-local.mjs
pnpm lint
pnpm build

echo "TinyAI engineering verification passed, including the independent v5 language-quality gate; see model/build/release-acceptance-v5.json."
