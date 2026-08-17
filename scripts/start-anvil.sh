#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.foundry/bin:$PATH"
exec anvil \
  --host 127.0.0.1 \
  --port 8545 \
  --chain-id 31337 \
  --gas-price 50000000 \
  --base-fee 1 \
  --gas-limit 55000000
