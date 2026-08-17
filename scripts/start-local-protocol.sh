#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$HOME/.local/bin:$PATH"
PROTOCOL_RPC_PORT="${PROTOCOL_RPC_PORT:-8545}"
PROTOCOL_CHAIN_ID="${PROTOCOL_CHAIN_ID:-1337}"
WEB_PORT="${WEB_PORT:-3004}"
PROTOCOL_RPC_URL="http://127.0.0.1:${PROTOCOL_RPC_PORT}"

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

anvil \
  --host 127.0.0.1 \
  --port "$PROTOCOL_RPC_PORT" \
  --chain-id "$PROTOCOL_CHAIN_ID" \
  --gas-price 50000000 \
  --base-fee 1 \
  --gas-limit 55000000 > /tmp/tinyai-protocol-anvil.log 2>&1 &
ANVIL_PID=$!

for _ in {1..30}; do
  if cast chain-id --rpc-url "$PROTOCOL_RPC_URL" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
if [[ "$(cast chain-id --rpc-url "$PROTOCOL_RPC_URL")" != "$PROTOCOL_CHAIN_ID" ]]; then
  echo "Local protocol Anvil did not start on chain $PROTOCOL_CHAIN_ID." >&2
  exit 1
fi

DEPLOY_OUTPUT="$(LOCAL_CHAIN_ID="$PROTOCOL_CHAIN_ID" RPC_URL="$PROTOCOL_RPC_URL" bash "$PROJECT_ROOT/scripts/deploy-local-protocol.sh")"
RETRIEVER_ADDRESS="$(sed -n 's/^retriever=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"
MODEL_ADDRESS="$(sed -n 's/^model=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"
LEXICON_ADDRESS="$(sed -n 's/^lexicon=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"
GENERATOR_ADDRESS="$(sed -n 's/^generator=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"
BRAIN_ADDRESS="$(sed -n 's/^brain=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"
REGISTRY_ADDRESS="$(sed -n 's/^registry=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"
COMPONENTS_ADDRESS="$(sed -n 's/^components=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"
PROTOCOL_ADDRESS="$(sed -n 's/^protocol=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"
MARKET_ADDRESS="$(sed -n 's/^market=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"

export RPC_URL="$PROTOCOL_RPC_URL"
export NEXT_PUBLIC_ENGINE_VERSION=6
export NEXT_PUBLIC_CHAIN_ID="$PROTOCOL_CHAIN_ID"
export NEXT_PUBLIC_CHAIN_NAME="Localhost 8545 (TinyAI)"
export NEXT_PUBLIC_NATIVE_SYMBOL=BNB
export NEXT_PUBLIC_EXPLORER_URL=
export NEXT_PUBLIC_WALLET_RPC_URL="$PROTOCOL_RPC_URL"
export NEXT_PUBLIC_CHAT_ADDRESS="$GENERATOR_ADDRESS"
export NEXT_PUBLIC_PROTOCOL_ADDRESS="$PROTOCOL_ADDRESS"
export NEXT_PUBLIC_COMPONENTS_ADDRESS="$COMPONENTS_ADDRESS"
export NEXT_PUBLIC_MARKET_ADDRESS="$MARKET_ADDRESS"
export NEXT_PUBLIC_BRAIN_REGISTRY_ADDRESS="$REGISTRY_ADDRESS"
export NEXT_PUBLIC_BUILD_LABEL="Genesis Brain V1 / TinyAI v6"
export RPC_ALLOWED_CONTRACTS="$RETRIEVER_ADDRESS,$MODEL_ADDRESS,$LEXICON_ADDRESS,$GENERATOR_ADDRESS,$BRAIN_ADDRESS,$REGISTRY_ADDRESS,$COMPONENTS_ADDRESS,$PROTOCOL_ADDRESS,$MARKET_ADDRESS"

cd "$PROJECT_ROOT/web"
pnpm dev --hostname 127.0.0.1 --port "$WEB_PORT" &
WEB_PID=$!

wait -n "$ANVIL_PID" "$WEB_PID"
