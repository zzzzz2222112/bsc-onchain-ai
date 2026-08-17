#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$HOME/.local/bin:$PATH"
V5_RPC_PORT="${V5_RPC_PORT:-8547}"
WEB_PORT="${WEB_PORT:-3002}"
V5_RPC_URL="http://127.0.0.1:${V5_RPC_PORT}"

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

anvil \
  --host 127.0.0.1 \
  --port "$V5_RPC_PORT" \
  --chain-id 31337 \
  --gas-price 50000000 \
  --base-fee 1 \
  --gas-limit 55000000 > /tmp/tinyai-v5-anvil.log 2>&1 &
ANVIL_PID=$!

for _ in {1..30}; do
  if cast chain-id --rpc-url "$V5_RPC_URL" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
if [[ "$(cast chain-id --rpc-url "$V5_RPC_URL")" != "31337" ]]; then
  echo "Local v5 Anvil did not start on chain 31337." >&2
  exit 1
fi

RPC_URL="$V5_RPC_URL" bash "$PROJECT_ROOT/scripts/deploy-local-v5.sh" >/dev/null
BASE_RUN_FILE="$PROJECT_ROOT/contracts/broadcast/Deploy.s.sol/31337/dry-run/run-latest.json"
V5_RUN_FILE="$PROJECT_ROOT/contracts/broadcast/DeployRetrievalV5.s.sol/31337/run-latest.json"
CLASSIFIER_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIChat") | .contractAddress' "$BASE_RUN_FILE" | tail -1)"
KNOWLEDGE_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIKnowledgeV5") | .contractAddress' "$V5_RUN_FILE" | tail -1)"
RETRIEVER_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIRetrieverV5") | .contractAddress' "$V5_RUN_FILE" | tail -1)"

export RPC_URL="$V5_RPC_URL"
export NEXT_PUBLIC_ENGINE_VERSION=5
export NEXT_PUBLIC_CHAIN_ID=31337
export NEXT_PUBLIC_CHAIN_NAME="Local Anvil v5"
export NEXT_PUBLIC_NATIVE_SYMBOL=ETH
export NEXT_PUBLIC_EXPLORER_URL=
export NEXT_PUBLIC_CHAT_ADDRESS="$RETRIEVER_ADDRESS"
export NEXT_PUBLIC_BUILD_LABEL="v5 / trained retrieval reasoner"
export RPC_ALLOWED_CONTRACTS="$CLASSIFIER_ADDRESS,$KNOWLEDGE_ADDRESS,$RETRIEVER_ADDRESS"

cd "$PROJECT_ROOT/web"
pnpm dev --hostname 127.0.0.1 --port "$WEB_PORT" &
WEB_PID=$!

wait -n "$ANVIL_PID" "$WEB_PID"
