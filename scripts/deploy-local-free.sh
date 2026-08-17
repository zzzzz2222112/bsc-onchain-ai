#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$HOME/.local/bin:$PATH"
export DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export TREASURY=0x0000000000000000000000000000000000000000
export CLI_SIGNER=true
export LIQUIDITY_RECIPIENT="$DEPLOYER"
export COMMUNITY_RECIPIENT="$DEPLOYER"
export DEPLOY_TOKEN=false
export PAYMENT_TOKEN=0x0000000000000000000000000000000000000000
export FEE_PER_CHAT=0
export BURN_BPS=0
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
LOCAL_CHAIN_ID="${LOCAL_CHAIN_ID:-31337}"

if [[ "$(cast chain-id --rpc-url "$RPC_URL")" != "$LOCAL_CHAIN_ID" ]]; then
  echo "Refusing to deploy the free test core outside local chain $LOCAL_CHAIN_ID." >&2
  exit 1
fi
if [[ "$(cast nonce "$DEPLOYER" --rpc-url "$RPC_URL")" != "0" ]]; then
  echo "The deterministic free-test deployer nonce is not zero; start a fresh local chain." >&2
  exit 1
fi

cd "$PROJECT_ROOT/contracts"
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  --sender "$DEPLOYER" \
  --unlocked \
  "$@"

SENDER="$DEPLOYER" \
RPC_URL="$RPC_URL" \
RUN_FILE="$PROJECT_ROOT/contracts/broadcast/Deploy.s.sol/$LOCAL_CHAIN_ID/dry-run/run-latest.json" \
EXPECTED_COUNT=26 \
EXPECTED_CHAIN_ID="$LOCAL_CHAIN_ID" \
bash "$PROJECT_ROOT/scripts/send-local-plan.sh"
