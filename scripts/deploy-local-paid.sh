#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$PATH"
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PAID_DEPLOYER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
TREASURY_ADDRESS="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
LIQUIDITY_ADDRESS="0x90F79bf6EB2c4f870365E785982E1f101E93b906"
COMMUNITY_ADDRESS="$PAID_DEPLOYER"
MODEL_CARD="$($HOME/.nvm/versions/node/v22.23.1/bin/node -e '
  const manifest = require(process.argv[1]);
  const model = manifest.contracts.find((item) => item.role === "modelCard");
  if (!model) throw new Error("local model card is missing from the manifest");
  process.stdout.write(model.address);
' "$PROJECT_ROOT/deployments/local-31337.json")"

if [[ "$(cast chain-id --rpc-url "$RPC_URL")" != "31337" ]]; then
  echo "Refusing to deploy the paid test contracts outside local chain 31337." >&2
  exit 1
fi
if [[ "$(cast nonce "$PAID_DEPLOYER" --rpc-url "$RPC_URL")" != "0" ]]; then
  echo "The deterministic paid-test deployer nonce is not zero; start a fresh local chain." >&2
  exit 1
fi
if [[ "$(cast code "$MODEL_CARD" --rpc-url "$RPC_URL")" == "0x" ]]; then
  echo "The verified local model card is not deployed." >&2
  exit 1
fi

cd "$PROJECT_ROOT/contracts"
CLI_SIGNER=true \
DEPLOYER="$PAID_DEPLOYER" \
MODEL_CARD="$MODEL_CARD" \
TREASURY="$TREASURY_ADDRESS" \
LIQUIDITY_RECIPIENT="$LIQUIDITY_ADDRESS" \
COMMUNITY_RECIPIENT="$COMMUNITY_ADDRESS" \
DEPLOY_TOKEN=true \
TOKEN_NAME="TinyAI Test Token" \
TOKEN_SYMBOL="TAIT" \
FEE_PER_CHAT=10000000000000000000 \
BURN_BPS=2500 \
forge script script/DeployPaidChat.s.sol:DeployPaidChat \
  --rpc-url "$RPC_URL" \
  --sender "$PAID_DEPLOYER" \
  --unlocked \
  "$@"

SENDER="$PAID_DEPLOYER" \
RUN_FILE="$PROJECT_ROOT/contracts/broadcast/DeployPaidChat.s.sol/31337/dry-run/run-latest.json" \
EXPECTED_COUNT=2 \
bash "$PROJECT_ROOT/scripts/send-local-plan.sh"
