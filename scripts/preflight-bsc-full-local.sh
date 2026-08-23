#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$HOME/.local/bin:$PATH"

: "${DEPLOYER:?DEPLOYER is required}"
: "${TREASURY:?TREASURY is required}"

if [[ ! "$DEPLOYER" =~ ^0x[0-9a-fA-F]{40}$ || ! "$TREASURY" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "Invalid deployer or treasury address." >&2
  exit 1
fi
if [[ "${DEPLOYER,,}" == "${TREASURY,,}" ]]; then
  echo "The deployer and treasury must be different addresses." >&2
  exit 1
fi

PORT="${PORT:-8558}"
RPC_URL="http://127.0.0.1:$PORT"
ANVIL_LOG="$(mktemp /tmp/tinyai-full-anvil56.XXXXXX.log)"

cleanup() {
  if [[ -n "${ANVIL_PID:-}" ]]; then
    kill "$ANVIL_PID" >/dev/null 2>&1 || true
    wait "$ANVIL_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

anvil \
  --host 127.0.0.1 \
  --port "$PORT" \
  --chain-id 56 \
  --gas-limit 55000000 \
  --auto-impersonate \
  --silent >"$ANVIL_LOG" 2>&1 &
ANVIL_PID=$!

for _ in $(seq 1 80); do
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

if [[ "$(cast chain-id --rpc-url "$RPC_URL")" != "56" ]]; then
  echo "The isolated chain-56 preflight did not start." >&2
  exit 1
fi

cast rpc --rpc-url "$RPC_URL" anvil_setBalance "$DEPLOYER" 0x56bc75e2d63100000 >/dev/null
if [[ "$(cast nonce "$DEPLOYER" --rpc-url "$RPC_URL")" != "0" ]]; then
  echo "The preflight deployer nonce is not zero." >&2
  exit 1
fi

cd "$PROJECT_ROOT/contracts"
export CLI_SIGNER=true
export PROTOCOL_OWNER="$DEPLOYER"
export COMPONENT_BASE_URI="${COMPONENT_BASE_URI:-ipfs://bafybeiduevofpggxdaxngsjfzyi4j5uvejtcwkffkh3hgoes6iuomptojm/{id}.json}"
forge script script/DeployFullProtocol.s.sol:DeployFullProtocol \
  --rpc-url "$RPC_URL" \
  --sender "$DEPLOYER" \
  --unlocked \
  --skip-simulation \
  --slow \
  --timeout 600 \
  --rpc-timeout 600 \
  --broadcast >/dev/null

RUN_FILE="$PROJECT_ROOT/contracts/broadcast/DeployFullProtocol.s.sol/56/run-latest.json"
if [[ ! -f "$RUN_FILE" ]]; then
  echo "The full-stack Forge run file was not created." >&2
  exit 1
fi

MODEL_CARD="$(jq -r '.transactions[] | select(.contractName == "TinyAIModelCard") | .contractAddress' "$RUN_FILE" | tail -1)"
CLASSIFIER="$(jq -r '.transactions[] | select(.contractName == "TinyAIChat") | .contractAddress' "$RUN_FILE" | tail -1)"
RETRIEVER="$(jq -r '.transactions[] | select(.contractName == "TinyAIRetrieverV5") | .contractAddress' "$RUN_FILE" | tail -1)"
GENERATOR="$(jq -r '.transactions[] | select(.contractName == "TinyAIGeneratorV6") | .contractAddress' "$RUN_FILE" | tail -1)"
BRAIN="$(jq -r '.transactions[] | select(.contractName == "TinyAIV6BrainEngine") | .contractAddress' "$RUN_FILE" | tail -1)"
REGISTRY="$(jq -r '.transactions[] | select(.contractName == "TinyAIBrainRegistry") | .contractAddress' "$RUN_FILE" | tail -1)"
COMPONENTS="$(jq -r '.transactions[] | select(.contractName == "TinyAIComponents") | .contractAddress' "$RUN_FILE" | tail -1)"
PROTOCOL="$(jq -r '.transactions[] | select(.contractName == "TinyAIProtocol") | .contractAddress' "$RUN_FILE" | tail -1)"
MARKET="$(jq -r '.transactions[] | select(.contractName == "TinyAIMarket") | .contractAddress' "$RUN_FILE" | tail -1)"

for value in "$MODEL_CARD" "$CLASSIFIER" "$RETRIEVER" "$GENERATOR" "$BRAIN" "$REGISTRY" "$COMPONENTS" "$PROTOCOL" "$MARKET"; do
  if [[ ! "$value" =~ ^0x[0-9a-fA-F]{40}$ || "$(cast code "$value" --rpc-url "$RPC_URL")" == "0x" ]]; then
    echo "A required full-stack contract is missing." >&2
    exit 1
  fi
done

if [[ "$(jq '.transactions | length' "$RUN_FILE")" != "45" ]]; then
  echo "The full-stack plan does not contain exactly 45 transactions." >&2
  exit 1
fi
if [[ "$(jq '[.transactions[] | select((.transaction.value // "0x0") != "0x0")] | length' "$RUN_FILE")" != "0" ]]; then
  echo "The full-stack plan contains a non-zero native value." >&2
  exit 1
fi

require_equal() {
  if [[ "$1" != "$2" ]]; then
    echo "Post-deployment check failed: $3" >&2
    exit 1
  fi
}

require_equal "$(cast call "$MODEL_CARD" 'integrityOk()(bool)' --rpc-url "$RPC_URL")" "true" "model integrity"
require_equal "$(cast call "$CLASSIFIER" 'VERSION()(uint8)' --rpc-url "$RPC_URL")" "3" "classifier version"
require_equal "$(cast call "$CLASSIFIER" 'feePerChat()(uint256)' --rpc-url "$RPC_URL")" "0" "classifier fee"
require_equal "$(cast call "$RETRIEVER" 'VERSION()(uint8)' --rpc-url "$RPC_URL")" "5" "retriever version"
require_equal "$(cast call "$RETRIEVER" 'integrityOk()(bool)' --rpc-url "$RPC_URL")" "true" "retriever integrity"
require_equal "$(cast call "$GENERATOR" 'VERSION()(uint8)' --rpc-url "$RPC_URL")" "6" "generator version"
require_equal "$(cast call "$GENERATOR" 'integrityOk()(bool)' --rpc-url "$RPC_URL")" "true" "generator integrity"
require_equal "$(cast call "$BRAIN" 'integrityOk()(bool)' --rpc-url "$RPC_URL")" "true" "brain integrity"
require_equal "$(cast call "$REGISTRY" 'recommendedVersion()(uint32)' --rpc-url "$RPC_URL")" "1" "recommended brain"
require_equal "$(cast call "$COMPONENTS" 'protocol()(address)' --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]')" "${PROTOCOL,,}" "component binding"
require_equal "$(cast call "$COMPONENTS" 'catalogSealed()(bool)' --rpc-url "$RPC_URL")" "true" "component seal"
require_equal "$(cast call "$COMPONENTS" 'MAX_COMPONENT_SUPPLY()(uint64)' --rpc-url "$RPC_URL" | awk '{print $1}')" "100000" "component cap"
require_equal "$(cast call "$COMPONENTS" 'MINT_PRICE()(uint128)' --rpc-url "$RPC_URL" | awk '{print $1}')" "100000000000000" "component price"
require_equal "$(cast call "$PROTOCOL" 'MAX_AI_SUPPLY()(uint256)' --rpc-url "$RPC_URL" | awk '{print $1}')" "10000" "AI cap"
require_equal "$(cast call "$PROTOCOL" 'MINT_PRICE()(uint256)' --rpc-url "$RPC_URL" | awk '{print $1}')" "100000000000000" "AI price"
require_equal "$(cast call "$MARKET" 'MARKET_FEE_BPS()(uint16)' --rpc-url "$RPC_URL" | awk '{print $1}')" "0" "market fee"
require_equal "$(cast call "$REGISTRY" 'owner()(address)' --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]')" "${DEPLOYER,,}" "registry owner"
require_equal "$(cast call "$COMPONENTS" 'owner()(address)' --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]')" "${DEPLOYER,,}" "component owner"
require_equal "$(cast call "$PROTOCOL" 'owner()(address)' --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]')" "${DEPLOYER,,}" "protocol owner"
require_equal "$(cast call "$COMPONENTS" 'treasury()(address)' --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]')" "${TREASURY,,}" "component treasury"
require_equal "$(cast call "$PROTOCOL" 'treasury()(address)' --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]')" "${TREASURY,,}" "protocol treasury"

printf 'status=PASSED_FULL_CHAIN_56_PREFLIGHT\ntransactions=45\nrun_file=%s\n' "$RUN_FILE"
