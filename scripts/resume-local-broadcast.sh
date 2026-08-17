#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

RPC_URL="http://127.0.0.1:8545"
SENDER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
RUN_FILE="$PROJECT_ROOT/contracts/broadcast/Deploy.s.sol/31337/dry-run/run-latest.json"

if [[ "$(cast chain-id --rpc-url "$RPC_URL")" != "31337" ]]; then
  echo "Refusing to resume: RPC is not the local Anvil chain" >&2
  exit 1
fi
if [[ ! -f "$RUN_FILE" ]]; then
  echo "Refusing to resume: the deterministic dry-run plan is missing" >&2
  exit 1
fi

SENDER="$SENDER" \
RUN_FILE="$RUN_FILE" \
EXPECTED_COUNT=26 \
bash "$PROJECT_ROOT/scripts/send-local-plan.sh"
