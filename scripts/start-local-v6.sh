#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$HOME/.local/bin:$PATH"
V6_RPC_PORT="${V6_RPC_PORT:-8548}"
WEB_PORT="${WEB_PORT:-3003}"
V6_RPC_URL="http://127.0.0.1:${V6_RPC_PORT}"

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

anvil \
  --host 127.0.0.1 \
  --port "$V6_RPC_PORT" \
  --chain-id 31337 \
  --gas-price 50000000 \
  --base-fee 1 \
  --gas-limit 55000000 > /tmp/tinyai-v6-anvil.log 2>&1 &
ANVIL_PID=$!

for _ in {1..30}; do
  if cast chain-id --rpc-url "$V6_RPC_URL" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
if [[ "$(cast chain-id --rpc-url "$V6_RPC_URL")" != "31337" ]]; then
  echo "Local v6 Anvil did not start on chain 31337." >&2
  exit 1
fi

DEPLOY_OUTPUT="$(RPC_URL="$V6_RPC_URL" bash "$PROJECT_ROOT/scripts/deploy-local-v6.sh")"
RETRIEVER_ADDRESS="$(sed -n 's/^retriever=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"
MODEL_ADDRESS="$(sed -n 's/^model=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"
LEXICON_ADDRESS="$(sed -n 's/^lexicon=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"
GENERATOR_ADDRESS="$(sed -n 's/^generator=//p' <<<"$DEPLOY_OUTPUT" | tail -1)"

export RPC_URL="$V6_RPC_URL"
export NEXT_PUBLIC_ENGINE_VERSION=6
export NEXT_PUBLIC_CHAIN_ID=31337
export NEXT_PUBLIC_CHAIN_NAME="Local Anvil v6"
export NEXT_PUBLIC_NATIVE_SYMBOL=ETH
export NEXT_PUBLIC_EXPLORER_URL=
export NEXT_PUBLIC_CHAT_ADDRESS="$GENERATOR_ADDRESS"
export NEXT_PUBLIC_BUILD_LABEL="v6 / on-chain neural token generator"
export RPC_ALLOWED_CONTRACTS="$RETRIEVER_ADDRESS,$MODEL_ADDRESS,$LEXICON_ADDRESS,$GENERATOR_ADDRESS"

cd "$PROJECT_ROOT/web"
pnpm dev --hostname 127.0.0.1 --port "$WEB_PORT" &
WEB_PID=$!

wait -n "$ANVIL_PID" "$WEB_PID"
