#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$HOME/.local/bin:$PATH"
export DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export CLI_SIGNER=true
RPC_URL="${RPC_URL:-http://127.0.0.1:8547}"
LOCAL_CHAIN_ID="${LOCAL_CHAIN_ID:-31337}"

if [[ "$(cast chain-id --rpc-url "$RPC_URL")" != "$LOCAL_CHAIN_ID" ]]; then
  echo "Refusing to deploy v5 outside local chain $LOCAL_CHAIN_ID." >&2
  exit 1
fi
if [[ "$(cast nonce "$DEPLOYER" --rpc-url "$RPC_URL")" != "0" ]]; then
  echo "The deterministic v5 deployer nonce is not zero; start a fresh local chain." >&2
  exit 1
fi

LOCAL_CHAIN_ID="$LOCAL_CHAIN_ID" RPC_URL="$RPC_URL" bash "$PROJECT_ROOT/scripts/deploy-local-free.sh" >/dev/null
BASE_RUN_FILE="$PROJECT_ROOT/contracts/broadcast/Deploy.s.sol/$LOCAL_CHAIN_ID/dry-run/run-latest.json"
CLASSIFIER_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIChat") | .contractAddress' "$BASE_RUN_FILE" | tail -1)"
if [[ ! "$CLASSIFIER_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "Could not recover the v3 classifier address." >&2
  exit 1
fi

cd "$PROJECT_ROOT/contracts"
CLASSIFIER="$CLASSIFIER_ADDRESS" forge script script/DeployRetrievalV5.s.sol:DeployRetrievalV5 \
  --rpc-url "$RPC_URL" \
  --sender "$DEPLOYER" \
  --unlocked \
  --broadcast

V5_RUN_FILE="$PROJECT_ROOT/contracts/broadcast/DeployRetrievalV5.s.sol/$LOCAL_CHAIN_ID/run-latest.json"
KNOWLEDGE_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIKnowledgeV5") | .contractAddress' "$V5_RUN_FILE" | tail -1)"
RETRIEVER_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIRetrieverV5") | .contractAddress' "$V5_RUN_FILE" | tail -1)"
if [[ ! "$KNOWLEDGE_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ || ! "$RETRIEVER_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "Could not recover both v5 deployment addresses." >&2
  exit 1
fi
if [[ "$(cast call "$RETRIEVER_ADDRESS" 'VERSION()(uint8)' --rpc-url "$RPC_URL")" != "5" ]]; then
  echo "The deployed retriever did not report version 5." >&2
  exit 1
fi
if [[ "$(cast call "$RETRIEVER_ADDRESS" 'integrityOk()(bool)' --rpc-url "$RPC_URL")" != "true" ]]; then
  echo "The deployed retriever failed its integrity check." >&2
  exit 1
fi

printf 'classifier=%s\nknowledge=%s\nretriever=%s\n' "$CLASSIFIER_ADDRESS" "$KNOWLEDGE_ADDRESS" "$RETRIEVER_ADDRESS"
