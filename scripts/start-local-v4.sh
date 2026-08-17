#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$PATH"
V4_RPC_PORT="${V4_RPC_PORT:-8546}"
WEB_PORT="${WEB_PORT:-3001}"
V4_RPC_URL="http://127.0.0.1:${V4_RPC_PORT}"

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

anvil \
  --host 127.0.0.1 \
  --port "$V4_RPC_PORT" \
  --chain-id 31337 \
  --gas-price 50000000 \
  --base-fee 1 \
  --gas-limit 55000000 &
ANVIL_PID=$!

for _ in {1..30}; do
  if cast chain-id --rpc-url "$V4_RPC_URL" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
if [[ "$(cast chain-id --rpc-url "$V4_RPC_URL")" != "31337" ]]; then
  echo "Local v4 Anvil did not start on chain 31337." >&2
  exit 1
fi

RPC_URL="$V4_RPC_URL" bash "$PROJECT_ROOT/scripts/deploy-local-v4.sh" >/dev/null
RUN_FILE="$PROJECT_ROOT/contracts/broadcast/DeployReasoningV4.s.sol/31337/run-latest.json"
KNOWLEDGE_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIKnowledgeV4") | .contractAddress' "$RUN_FILE" | tail -1)"
REASONER_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIReasonerV4") | .contractAddress' "$RUN_FILE" | tail -1)"

export RPC_URL="$V4_RPC_URL"
export NEXT_PUBLIC_ENGINE_VERSION=4
export NEXT_PUBLIC_CHAIN_ID=31337
export NEXT_PUBLIC_CHAIN_NAME="Local Anvil v4"
export NEXT_PUBLIC_NATIVE_SYMBOL=ETH
export NEXT_PUBLIC_EXPLORER_URL=
export NEXT_PUBLIC_CHAT_ADDRESS="$REASONER_ADDRESS"
export NEXT_PUBLIC_BUILD_LABEL="v4.1 / local universal reasoner"
export RPC_ALLOWED_CONTRACTS="$KNOWLEDGE_ADDRESS,$REASONER_ADDRESS"

cd "$PROJECT_ROOT/web"
pnpm dev --hostname 127.0.0.1 --port "$WEB_PORT" &
WEB_PID=$!

wait -n "$ANVIL_PID" "$WEB_PID"
