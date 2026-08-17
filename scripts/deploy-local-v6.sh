#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$HOME/.local/bin:$PATH"
export DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export CLI_SIGNER=true
RPC_URL="${RPC_URL:-http://127.0.0.1:8548}"
LOCAL_CHAIN_ID="${LOCAL_CHAIN_ID:-31337}"

if [[ "$(cast chain-id --rpc-url "$RPC_URL")" != "$LOCAL_CHAIN_ID" ]]; then
  echo "Refusing to deploy v6 outside local chain $LOCAL_CHAIN_ID." >&2
  exit 1
fi
if [[ "$(cast nonce "$DEPLOYER" --rpc-url "$RPC_URL")" != "0" ]]; then
  echo "The deterministic v6 deployer nonce is not zero; start a fresh local chain." >&2
  exit 1
fi

LOCAL_CHAIN_ID="$LOCAL_CHAIN_ID" RPC_URL="$RPC_URL" bash "$PROJECT_ROOT/scripts/deploy-local-v5.sh" >/dev/null
V5_RUN_FILE="$PROJECT_ROOT/contracts/broadcast/DeployRetrievalV5.s.sol/$LOCAL_CHAIN_ID/run-latest.json"
RETRIEVER_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIRetrieverV5") | .contractAddress' "$V5_RUN_FILE" | tail -1)"
if [[ ! "$RETRIEVER_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "Could not recover the v5 retriever address." >&2
  exit 1
fi

cd "$PROJECT_ROOT/contracts"
RETRIEVER="$RETRIEVER_ADDRESS" forge script script/DeployGeneratorV6.s.sol:DeployGeneratorV6 \
  --rpc-url "$RPC_URL" \
  --sender "$DEPLOYER" \
  --unlocked \
  --broadcast

V6_RUN_FILE="$PROJECT_ROOT/contracts/broadcast/DeployGeneratorV6.s.sol/$LOCAL_CHAIN_ID/run-latest.json"
MODEL_ADDRESS="$(jq -r '.transactions[] | select(.transactionType == "CREATE") | .contractAddress' "$V6_RUN_FILE" | sed -n '1p')"
LEXICON_ADDRESS="$(jq -r '.transactions[] | select(.transactionType == "CREATE") | .contractAddress' "$V6_RUN_FILE" | sed -n '2p')"
GENERATOR_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIGeneratorV6") | .contractAddress' "$V6_RUN_FILE" | tail -1)"
if [[ ! "$MODEL_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ || ! "$LEXICON_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ || ! "$GENERATOR_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "Could not recover all v6 deployment addresses." >&2
  exit 1
fi
if [[ "$(cast call "$GENERATOR_ADDRESS" 'VERSION()(uint8)' --rpc-url "$RPC_URL")" != "6" ]]; then
  echo "The deployed generator did not report version 6." >&2
  exit 1
fi
if [[ "$(cast call "$GENERATOR_ADDRESS" 'integrityOk()(bool)' --rpc-url "$RPC_URL")" != "true" ]]; then
  echo "The deployed generator failed its integrity check." >&2
  exit 1
fi

printf 'retriever=%s\nmodel=%s\nlexicon=%s\ngenerator=%s\n' "$RETRIEVER_ADDRESS" "$MODEL_ADDRESS" "$LEXICON_ADDRESS" "$GENERATOR_ADDRESS"
