#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.foundry/bin:$PATH"
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
SENDER="${SENDER:?SENDER is required}"
RUN_FILE="${RUN_FILE:?RUN_FILE is required}"
EXPECTED_COUNT="${EXPECTED_COUNT:?EXPECTED_COUNT is required}"
EXPECTED_CHAIN_ID="${EXPECTED_CHAIN_ID:-31337}"

if [[ ! "$RPC_URL" =~ ^http://(127\.0\.0\.1|localhost):[0-9]+/?$ ]]; then
  echo "Refusing a local plan against a non-loopback RPC URL." >&2
  exit 1
fi
if [[ "$(cast chain-id --rpc-url "$RPC_URL")" != "$EXPECTED_CHAIN_ID" ]]; then
  echo "Refusing local plan: expected chain $EXPECTED_CHAIN_ID." >&2
  exit 1
fi
if [[ "$(cast rpc --rpc-url "$RPC_URL" web3_clientVersion)" != *anvil* ]]; then
  echo "Refusing local plan against a non-Anvil client." >&2
  exit 1
fi
if [[ ! -f "$RUN_FILE" ]]; then
  echo "Planned transaction file does not exist: $RUN_FILE" >&2
  exit 1
fi
if [[ "$(jq '.transactions | length' "$RUN_FILE")" != "$EXPECTED_COUNT" ]]; then
  echo "Expected $EXPECTED_COUNT planned transactions." >&2
  exit 1
fi

for index in $(seq 0 $((EXPECTED_COUNT - 1))); do
  planned_nonce="$(jq -r ".transactions[$index].transaction.nonce" "$RUN_FILE")"
  current_nonce="$(cast nonce "$SENDER" --rpc-url "$RPC_URL")"
  if (( current_nonce > planned_nonce )); then
    continue
  fi
  if (( current_nonce != planned_nonce )); then
    echo "Refusing plan item $index: expected sender nonce $planned_nonce, got $current_nonce." >&2
    exit 1
  fi

  input="$(jq -r ".transactions[$index].transaction.input" "$RUN_FILE")"
  gas_limit="$(jq -r ".transactions[$index].transaction.gas" "$RUN_FILE")"
  native_value="$(jq -r ".transactions[$index].transaction.value // \"0x0\"" "$RUN_FILE")"
  expected_address="$(jq -r ".transactions[$index].contractAddress" "$RUN_FILE")"
  if [[ "$native_value" != "0x0" && "$native_value" != "0" ]]; then
    echo "Refusing non-zero native value in local plan item $index." >&2
    exit 1
  fi

  receipt="$(cast send \
    --from "$SENDER" \
    --unlocked \
    --nonce "$planned_nonce" \
    --gas-limit "$gas_limit" \
    --gas-price 50000000 \
    --legacy \
    --confirmations 1 \
    --timeout 60 \
    --rpc-url "$RPC_URL" \
    --json \
    --create "$input")"

  status="$(jq -r '.status' <<<"$receipt")"
  actual_address="$(jq -r '.contractAddress' <<<"$receipt")"
  tx_hash="$(jq -r '.transactionHash' <<<"$receipt")"
  gas_used="$(jq -r '.gasUsed' <<<"$receipt")"
  if [[ "$status" != "0x1" || "${actual_address,,}" != "${expected_address,,}" ]]; then
    echo "Plan verification failed for item $index / nonce $planned_nonce." >&2
    exit 1
  fi
  printf 'index=%s nonce=%s address=%s gasUsed=%s tx=%s\n' "$index" "$planned_nonce" "$actual_address" "$gas_used" "$tx_hash"
done
