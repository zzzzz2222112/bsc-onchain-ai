#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$PATH"
NODE="$HOME/.nvm/versions/node/v22.23.1/bin/node"

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

anvil \
  --host 127.0.0.1 \
  --port 8545 \
  --chain-id 31337 \
  --gas-price 50000000 \
  --base-fee 1 \
  --gas-limit 55000000 &
ANVIL_PID=$!

for _ in {1..30}; do
  if cast chain-id --rpc-url http://127.0.0.1:8545 >/dev/null 2>&1; then break; fi
  sleep 0.2
done
if [[ "$(cast chain-id --rpc-url http://127.0.0.1:8545)" != "31337" ]]; then
  echo "Local Anvil did not start on chain 31337." >&2
  exit 1
fi

bash "$PROJECT_ROOT/scripts/deploy-local-free.sh" >/dev/null
node "$PROJECT_ROOT/scripts/audit-local-deployment.mjs" --verify-manifest >/dev/null
bash "$PROJECT_ROOT/scripts/deploy-local-paid.sh" >/dev/null

export RPC_URL=http://127.0.0.1:8545
export NEXT_PUBLIC_CHAIN_ID=31337
export NEXT_PUBLIC_CHAIN_NAME="Local Anvil"
export NEXT_PUBLIC_NATIVE_SYMBOL=ETH
export NEXT_PUBLIC_EXPLORER_URL=
export NEXT_PUBLIC_CHAT_ADDRESS="$($NODE -e '
  const paid = require(process.argv[1]);
  process.stdout.write(paid.paidChat.address);
' "$PROJECT_ROOT/deployments/local-paid-31337.json")"
export NEXT_PUBLIC_BUILD_LABEL="v3 / local paid demo / model 3a07dd51"
export RPC_ALLOWED_CONTRACTS="$($NODE -e '
  const free = require(process.argv[1]);
  const paid = require(process.argv[2]);
  process.stdout.write([...free.contracts.map((item) => item.address), paid.token.address, paid.paidChat.address].join(","));
' "$PROJECT_ROOT/deployments/local-31337.json" "$PROJECT_ROOT/deployments/local-paid-31337.json")"

cd "$PROJECT_ROOT/web"
pnpm dev --hostname 127.0.0.1 --port 3000 &
WEB_PID=$!

wait -n "$ANVIL_PID" "$WEB_PID"
