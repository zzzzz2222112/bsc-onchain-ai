#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.nvm/versions/node/v22.23.1/bin:$HOME/.foundry/bin:$HOME/.local/bin:$PATH"
export DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export CLI_SIGNER=true
RPC_URL="${RPC_URL:-http://127.0.0.1:8549}"
LOCAL_CHAIN_ID="${LOCAL_CHAIN_ID:-31337}"

if [[ "$(cast chain-id --rpc-url "$RPC_URL")" != "$LOCAL_CHAIN_ID" ]]; then
  echo "Refusing to deploy the protocol outside local chain $LOCAL_CHAIN_ID." >&2
  exit 1
fi
if [[ "$(cast nonce "$DEPLOYER" --rpc-url "$RPC_URL")" != "0" ]]; then
  echo "The deterministic protocol deployer nonce is not zero; start a fresh local chain." >&2
  exit 1
fi

V6_OUTPUT="$(LOCAL_CHAIN_ID="$LOCAL_CHAIN_ID" RPC_URL="$RPC_URL" bash "$PROJECT_ROOT/scripts/deploy-local-v6.sh")"
RETRIEVER_ADDRESS="$(sed -n 's/^retriever=//p' <<<"$V6_OUTPUT" | tail -1)"
MODEL_ADDRESS="$(sed -n 's/^model=//p' <<<"$V6_OUTPUT" | tail -1)"
LEXICON_ADDRESS="$(sed -n 's/^lexicon=//p' <<<"$V6_OUTPUT" | tail -1)"
GENERATOR_ADDRESS="$(sed -n 's/^generator=//p' <<<"$V6_OUTPUT" | tail -1)"
if [[ ! "$GENERATOR_ADDRESS" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "Could not recover the v6 generator address." >&2
  exit 1
fi

cd "$PROJECT_ROOT/contracts"
GENERATOR_V6="$GENERATOR_ADDRESS" PROTOCOL_OWNER="$DEPLOYER" TREASURY="$DEPLOYER" \
  forge script script/DeployProtocol.s.sol:DeployProtocol \
    --rpc-url "$RPC_URL" \
    --sender "$DEPLOYER" \
    --unlocked \
    --broadcast >/dev/null

RUN_FILE="$PROJECT_ROOT/contracts/broadcast/DeployProtocol.s.sol/$LOCAL_CHAIN_ID/run-latest.json"
BRAIN_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIV6BrainEngine") | .contractAddress' "$RUN_FILE" | tail -1)"
REGISTRY_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIBrainRegistry") | .contractAddress' "$RUN_FILE" | tail -1)"
COMPONENTS_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIComponents") | .contractAddress' "$RUN_FILE" | tail -1)"
PROTOCOL_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIProtocol") | .contractAddress' "$RUN_FILE" | tail -1)"
MARKET_ADDRESS="$(jq -r '.transactions[] | select(.contractName == "TinyAIMarket") | .contractAddress' "$RUN_FILE" | tail -1)"

for value in "$BRAIN_ADDRESS" "$REGISTRY_ADDRESS" "$COMPONENTS_ADDRESS" "$PROTOCOL_ADDRESS" "$MARKET_ADDRESS"; do
  if [[ ! "$value" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "Could not recover every protocol deployment address." >&2
    exit 1
  fi
done

if [[ "$(cast call "$REGISTRY_ADDRESS" 'recommendedVersion()(uint32)' --rpc-url "$RPC_URL")" != "1" ]]; then
  echo "The protocol registry did not recommend Genesis Brain V1." >&2
  exit 1
fi
if [[ "$(cast call "$BRAIN_ADDRESS" 'integrityOk()(bool)' --rpc-url "$RPC_URL")" != "true" ]]; then
  echo "Genesis Brain V1 failed its integrity check." >&2
  exit 1
fi
if [[ "$(cast call "$COMPONENTS_ADDRESS" 'protocol()(address)' --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]')" != "$(tr '[:upper:]' '[:lower:]' <<<"$PROTOCOL_ADDRESS")" ]]; then
  echo "The component contract is not bound to the AI protocol." >&2
  exit 1
fi
if [[ "$(cast call "$PROTOCOL_ADDRESS" 'MAX_AI_SUPPLY()(uint256)' --rpc-url "$RPC_URL")" != "10000" ]]; then
  echo "The AI supply cap is not permanently fixed at 10,000." >&2
  exit 1
fi
if [[ "$(cast call "$PROTOCOL_ADDRESS" 'MINT_PRICE()(uint256)' --rpc-url "$RPC_URL")" != "100000000000000" ]]; then
  echo "The AI mint price is not fixed at 0.0001 BNB." >&2
  exit 1
fi
if [[ "$(cast call "$COMPONENTS_ADDRESS" 'MAX_COMPONENT_SUPPLY()(uint64)' --rpc-url "$RPC_URL")" != "100000" ]]; then
  echo "The component supply cap is not permanently fixed at 100,000." >&2
  exit 1
fi
if [[ "$(cast call "$COMPONENTS_ADDRESS" 'MINT_PRICE()(uint128)' --rpc-url "$RPC_URL")" != "100000000000000" ]]; then
  echo "The component mint price is not fixed at 0.0001 BNB." >&2
  exit 1
fi
if [[ "$(cast call "$COMPONENTS_ADDRESS" 'totalDefinedCap()(uint64)' --rpc-url "$RPC_URL")" != "100000" ]]; then
  echo "The six component allocations do not add up to 100,000." >&2
  exit 1
fi
if [[ "$(cast call "$COMPONENTS_ADDRESS" 'catalogSealed()(bool)' --rpc-url "$RPC_URL")" != "true" ]]; then
  echo "The genesis component catalog was not permanently sealed." >&2
  exit 1
fi
if [[ "$(cast call "$MARKET_ADDRESS" 'MARKET_FEE_BPS()(uint16)' --rpc-url "$RPC_URL")" != "0" ]]; then
  echo "The market fee is not permanently fixed at zero." >&2
  exit 1
fi

printf 'retriever=%s\nmodel=%s\nlexicon=%s\ngenerator=%s\nbrain=%s\nregistry=%s\ncomponents=%s\nprotocol=%s\nmarket=%s\n' \
  "$RETRIEVER_ADDRESS" "$MODEL_ADDRESS" "$LEXICON_ADDRESS" "$GENERATOR_ADDRESS" "$BRAIN_ADDRESS" \
  "$REGISTRY_ADDRESS" "$COMPONENTS_ADDRESS" "$PROTOCOL_ADDRESS" "$MARKET_ADDRESS"
