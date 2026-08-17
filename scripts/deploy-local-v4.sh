#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"
export DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export CLI_SIGNER=true
RPC_URL="${RPC_URL:-http://127.0.0.1:8546}"

if [[ "$(cast chain-id --rpc-url "$RPC_URL")" != "31337" ]]; then
  echo "Refusing to deploy v4 outside local chain 31337." >&2
  exit 1
fi
if [[ "$(cast nonce "$DEPLOYER" --rpc-url "$RPC_URL")" != "0" ]]; then
  echo "The deterministic v4 deployer nonce is not zero; start a fresh local chain." >&2
  exit 1
fi

cd "$PROJECT_ROOT/contracts"
forge script script/DeployReasoningV4.s.sol:DeployReasoningV4 \
  --rpc-url "$RPC_URL" \
  --sender "$DEPLOYER" \
  --unlocked \
  --broadcast

RUN_FILE="$PROJECT_ROOT/contracts/broadcast/DeployReasoningV4.s.sol/31337/run-latest.json"
KNOWLEDGE_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIKnowledgeV4") | .contractAddress' "$RUN_FILE" | tail -1)"
REASONER_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIReasonerV4") | .contractAddress' "$RUN_FILE" | tail -1)"

if [[ ! "$KNOWLEDGE_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ || ! "$REASONER_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "Could not recover both v4 deployment addresses." >&2
  exit 1
fi
if [[ "$(cast call "$REASONER_ADDRESS" 'VERSION()(uint8)' --rpc-url "$RPC_URL")" != "4" ]]; then
  echo "The deployed reasoner did not report version 4." >&2
  exit 1
fi
if [[ "$(cast call "$REASONER_ADDRESS" 'integrityOk()(bool)' --rpc-url "$RPC_URL")" != "true" ]]; then
  echo "The deployed reasoner failed its knowledge integrity check." >&2
  exit 1
fi

printf 'knowledge=%s\nreasoner=%s\n' "$KNOWLEDGE_ADDRESS" "$REASONER_ADDRESS"
