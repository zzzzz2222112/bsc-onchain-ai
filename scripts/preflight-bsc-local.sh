#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

RPC_URL="${RPC_URL:-http://127.0.0.1:8556}"
PORT="${PORT:-8556}"
SENDER="${SENDER:-0x2d7E447136D57b9D6B5FcAACFc10F56c9E4Ebf25}"
ANVIL_LOG="$(mktemp /tmp/tinyai-anvil56.XXXXXX.log)"
ANVIL_PID=""
AUDIT_REPORT="${BSC_PREFLIGHT_AUDIT_REPORT:-}"

cleanup() {
  if [[ -n "$ANVIL_PID" ]] && kill -0 "$ANVIL_PID" 2>/dev/null; then
    kill "$ANVIL_PID" 2>/dev/null || true
    wait "$ANVIL_PID" 2>/dev/null || true
  fi
  rm -f "$ANVIL_LOG"
}
trap cleanup EXIT INT TERM

anvil \
  --host 127.0.0.1 \
  --port "$PORT" \
  --chain-id 56 \
  --gas-price 50000000 \
  --base-fee 1 \
  --gas-limit 55000000 \
  >"$ANVIL_LOG" 2>&1 &
ANVIL_PID=$!

for _ in $(seq 1 50); do
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if [[ "$(cast chain-id --rpc-url "$RPC_URL")" != "56" ]]; then
  echo "Local BSC preflight chain did not start with chain ID 56." >&2
  exit 1
fi

cast rpc --rpc-url "$RPC_URL" anvil_impersonateAccount "$SENDER" >/dev/null
cast rpc --rpc-url "$RPC_URL" anvil_setBalance "$SENDER" 0x56bc75e2d63100000 >/dev/null

cd "$PROJECT_ROOT/contracts"
CLI_SIGNER=true \
DEPLOYER="$SENDER" \
TREASURY=0x0000000000000000000000000000000000000000 \
LIQUIDITY_RECIPIENT="$SENDER" \
COMMUNITY_RECIPIENT="$SENDER" \
DEPLOY_TOKEN=false \
PAYMENT_TOKEN=0x0000000000000000000000000000000000000000 \
FEE_PER_CHAT=0 \
BURN_BPS=0 \
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  --sender "$SENDER" \
  --unlocked \
  --legacy \
  --with-gas-price 50000000

RUN_FILE="$PROJECT_ROOT/contracts/broadcast/Deploy.s.sol/56/dry-run/run-latest.json"
if [[ "$(jq '.transactions | length' "$RUN_FILE")" != "26" ]]; then
  echo "BSC preflight must contain exactly 26 CREATE transactions." >&2
  exit 1
fi

for index in $(seq 0 25); do
  nonce="$(jq -r ".transactions[$index].transaction.nonce" "$RUN_FILE")"
  nonce_decimal="$(cast to-dec "$nonce")"
  value="$(jq -r ".transactions[$index].transaction.value // \"0x0\"" "$RUN_FILE")"
  address="$(jq -r ".transactions[$index].contractAddress" "$RUN_FILE")"
  if [[ "$nonce_decimal" != "$index" ]]; then
    echo "Unexpected nonce at plan index $index: $nonce." >&2
    exit 1
  fi
  if [[ "$value" != "0x0" && "$value" != "0" ]]; then
    echo "Non-zero native value at plan index $index." >&2
    exit 1
  fi
  if [[ ! "$address" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "Missing CREATE address at plan index $index." >&2
    exit 1
  fi
done

RPC_URL="$RPC_URL" \
SENDER="$SENDER" \
RUN_FILE="$RUN_FILE" \
EXPECTED_COUNT=26 \
EXPECTED_CHAIN_ID=56 \
bash "$PROJECT_ROOT/scripts/send-local-plan.sh" >/dev/null

if [[ -n "$AUDIT_REPORT" ]]; then
  "$HOME/.nvm/versions/node/v22.23.1/bin/node" "$PROJECT_ROOT/scripts/audit-core-deployment.mjs" \
    --manifest "$PROJECT_ROOT/deployments/bsc-mainnet-core-draft.json" \
    --rpc-url "$RPC_URL" \
    >"$AUDIT_REPORT"
else
  "$HOME/.nvm/versions/node/v22.23.1/bin/node" "$PROJECT_ROOT/scripts/audit-core-deployment.mjs" \
    --manifest "$PROJECT_ROOT/deployments/bsc-mainnet-core-draft.json" \
    --rpc-url "$RPC_URL" \
    >/dev/null
fi

model_card="$(jq -r '.transactions[24].contractAddress' "$RUN_FILE")"
chat="$(jq -r '.transactions[25].contractAddress' "$RUN_FILE")"

printf 'status=PASSED_LOCAL_CHAIN_56_DRY_RUN\n'
printf 'sender=%s\n' "$SENDER"
printf 'transactionCount=26\n'
printf 'nativeValueWei=0\n'
printf 'modelCard=%s\n' "$model_card"
printf 'freeChatEngine=%s\n' "$chat"
printf 'runFile=%s\n' "$RUN_FILE"
