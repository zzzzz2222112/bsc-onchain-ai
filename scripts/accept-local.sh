#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$PATH"
NODE="$HOME/.nvm/versions/node/v22.23.1/bin/node"
CAST="$HOME/.foundry/bin/cast"
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
FRONTEND_URL="${FRONTEND_URL:-http://127.0.0.1:3000}"

read_manifest_field() {
  "$NODE" -e '
    const manifest = require(process.argv[1]);
    const role = process.argv[2];
    const contract = manifest.contracts.find((item) => item.role === role);
    if (!contract) throw new Error(`missing manifest role ${role}`);
    process.stdout.write(contract.address);
  ' "$PROJECT_ROOT/deployments/local-31337.json" "$1"
}

if [[ "$($CAST chain-id --rpc-url "$RPC_URL")" != "31337" ]]; then
  echo "Refusing to accept a chain other than local chain 31337." >&2
  exit 1
fi

MODEL_CARD="$(read_manifest_field modelCard)"
CHAT_ENGINE="$(read_manifest_field freeChatEngine)"

"$NODE" "$PROJECT_ROOT/scripts/audit-local-deployment.mjs" --verify-manifest >/dev/null

if [[ "$($CAST call "$MODEL_CARD" 'integrityOk()(bool)' --rpc-url "$RPC_URL")" != "true" ]]; then
  echo "Model-card integrity check failed." >&2
  exit 1
fi

if [[ "$($CAST call "$CHAT_ENGINE" 'feePerChat()(uint256)' --rpc-url "$RPC_URL")" != "0" ]]; then
  echo "Expected the local core to be fee-free." >&2
  exit 1
fi

TOTAL_CHATS="$($CAST call "$CHAT_ENGINE" 'totalChats()(uint64)' --rpc-url "$RPC_URL")"
if (( TOTAL_CHATS < 1 )); then
  echo "Expected at least one persisted local chat proof." >&2
  exit 1
fi

curl --fail --silent --show-error "$FRONTEND_URL" >/dev/null
(
  cd "$PROJECT_ROOT/web"
  pnpm smoke
)

echo "Local acceptance passed: 26 live code hashes, model integrity, fee-free economics, persisted chat, and restricted frontend RPC."
