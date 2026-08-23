# Flap Token Mode

## Status

This repository contains a prelaunch Token Mode for a brand-new Flap Tax Token V3. The future token address is mined locally with CREATE2 and may be bound to the TinyAI contracts before the token is created. The Token Mode stack and the new token are **not deployed to BSC mainnet yet**, so this document contains no canonical production addresses.

The live BNB-settled TinyAI deployment remains a separate edition. Do not combine its addresses with Token Mode.

## Fixed economic boundary

- Token identity: `TinyAI` (`TINYAI`).
- Public website: `https://bnbtinyai.org`.
- Public X account: `https://x.com/Tinyaipro`.
- Pinned token metadata: `QmcFiqZScoop6uDjpPzsxTuSkcEZGLs13iZjSHqFqhY2Qy`.
- Pinned 1024 x 1024 avatar: `Qmc1LroY5RzZCPzkmQK9oKDWWWaLHouUtbhhHEdahxX6Aq`.
- Flap quote/liquidity asset: BSC `NVIDIA Corp` (`NVDAB`), `0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436`, 18 decimals.
- Flap transfer tax: `1%` on buys and `1%` on sells for exactly `30 days` (`2,592,000` seconds) from launch; the configured temporary tax then expires according to the Flap token implementation.
- AI Mint: `500` units of the new Flap token, paid directly to TinyAI Treasury.
- One component Mint: `500` units of the new Flap token, paid directly to TinyAI Treasury.
- Persistent chat and brain upgrades: zero protocol-token charge; the user still pays BSC gas.
- TinyAI secondary market fee: zero; the seller receives the full listed token price.
- Flap buy/sell tax beneficiary: `TinyAIHolderVault`.
- Reward rule: one TinyAI NFT equals one reward share, regardless of wallet concentration.

`NVDAB` is an on-chain quote asset selected by this deployment. TinyAI does not represent it as NVIDIA equity and does not add redemption, custody or shareholder rights to that token.

## Two independent money paths

```text
AI/component Mint
user -- new Flap token --> TinyAI Treasury

Tax reward
taxed Flap trade --> Flap TaxProcessor --> NVDAB beneficiary allocation
                  --> TinyAIHolderVault --> current TinyAI NFT holders
```

Mint income and trade-tax rewards do not mix. Flap-level protocol and commission deductions are applied before the beneficiary allocation. Setting `mktBps=10000` directs the full beneficiary allocation to the Vault; it does not mean that 100% of gross trading tax reaches TinyAI holders.

Rewards attach to the AI identity:

- a newly minted AI cannot claim rewards allocated before it existed;
- revenue received before the first AI exists stays permanently unallocated;
- unclaimed rewards follow the AI when the NFT is transferred;
- any caller may synchronize newly received NVDAB, but only the current AI owner can claim that AI's rewards;
- the Vault has no owner withdrawal function for reward funds.

## Deterministic prelaunch sequence

The token is intentionally created last:

1. Set `FLAP_SALT_OUTPUT` to a new private path outside the repository, then run `web/scripts/mine-flap-salt.mjs` locally to find a Tax V3 address ending in `7777`. The script writes the salt only to that new file and prints only the safe predicted CA. Keep the file outside Git and public logs.
2. Choose the launch path explicitly. This release uses an unlocked salt and sets `FLAP_REQUIRE_SALT_LOCK=false`; that avoids a reservation fee but accepts public-mempool front-running risk. Operators who prefer reservation may instead use `LockFlapSaltForTinyAI.s.sol` after separately verifying and approving the live Portal fee.
3. Deploy `TinyAIHolderVault` with immutable reward token `NVDAB`.
4. Deploy Token Mode Components, Protocol and Market against the empty predicted token address. Bind the Vault and Components to the Protocol once.
5. Simulate `Portal.newTokenV6` and require its return value to equal the prebound address.
6. Create the Flap token with `NVDAB` as quote token, `quoteAmt=0`, the Vault as beneficiary and `mktBps=10000`.
7. Read back token, quote token, TaxProcessor, Vault binding, payment-token binding, tax configuration and code hashes before enabling the frontend.

An **unlocked** salt becomes visible in the public mempool and can be copied by a front-runner. The creation script still requires a deployer-owned Tax V3 lock by default as a fail-closed safety setting. This release deliberately overrides it with `FLAP_REQUIRE_SALT_LOCK=false`: the script accepts only a completely empty lock entry and still aborts if another address has locked the salt. Keep the salt outside logs and Git before launch, while recognizing that privacy before submission does not protect it after public broadcast.

With an ERC-20 quote asset, Flap currently documents an additional `1 gwei` native value on tax-token creation. `quoteAmt=0` means no initial NVDAB inventory is deposited; it does not remove normal BSC deployment gas or that interface-required `1 gwei` value.

Before the final launch, verify that the live Portal still uses the Tax V3 implementation assumed by the address miner. The launch simulation must fail closed if the computed or returned address changes.

## Contracts

- `ExactERC20Payment.sol`: exact recipient-balance accounting and a prelaunch guard that rejects payment while the predicted token has no code.
- `TinyAITokenComponents.sol`: ERC-1155 component Mint paid in the new token.
- `TinyAITokenProtocol.sol`: ERC-721 AI Mint, owner-only state changes and one-time Vault registration.
- `TinyAITokenMarket.sol`: non-custodial fixed-price listings with zero protocol market fee.
- `TinyAIHolderVault.sol`: O(1) NVDAB reward accumulator keyed by AI ID.
- `LockFlapSaltForTinyAI.s.sol`: reserve the future Tax V3 address with an explicitly pinned fee.
- `DeployAIHolderVault.s.sol`: deploy the immutable NVDAB reward Vault.
- `DeployTokenProtocol.s.sol`: predeploy and bind the Token Mode stack against the empty predicted CA.
- `CreateFlapTokenForTinyAI.s.sol`: create the NVDAB-quoted Flap token last and verify the binding.

All Token Mode contracts pin one payment-token address at construction. Changing the token requires a separate edition or an explicitly designed migration; it is not a frontend setting.

## Configuration

Private launch configuration:

```dotenv
FLAP_QUOTE_TOKEN=0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436
FLAP_TOKEN_NAME=TinyAI
FLAP_TOKEN_SYMBOL=TINYAI
FLAP_TOKEN_META=QmcFiqZScoop6uDjpPzsxTuSkcEZGLs13iZjSHqFqhY2Qy
FLAP_TOKEN_SALT=0xPrivateUntilLaunch
FLAP_REQUIRE_SALT_LOCK=false
FLAP_BUY_TAX_BPS=100
FLAP_SELL_TAX_BPS=100
FLAP_TAX_DURATION=2592000
PAYMENT_TOKEN=0xPredicted7777Address
HOLDER_VAULT=0xDeployedHolderVault
AI_MINT_PRICE=500000000000000000000
COMPONENT_MINT_PRICE=500000000000000000000
CHAT_PRICE=0
FLAP_INITIAL_QUOTE_AMOUNT=0
FLAP_CALL_VALUE=1000000000
```

Public frontend configuration after verified deployment:

```dotenv
NEXT_PUBLIC_SETTLEMENT_MODE=token
NEXT_PUBLIC_PAYMENT_TOKEN_ADDRESS=0xCreatedFlapToken
NEXT_PUBLIC_PAYMENT_TOKEN_SYMBOL=TINYAI
NEXT_PUBLIC_PAYMENT_TOKEN_DECIMALS=18
NEXT_PUBLIC_HOLDER_VAULT_ADDRESS=0xTinyAIHolderVault
NEXT_PUBLIC_REWARD_ASSET_SYMBOL=NVDAB
NEXT_PUBLIC_REWARD_ASSET_DECIMALS=18
NEXT_PUBLIC_PROTOCOL_ADDRESS=0xTokenProtocol
NEXT_PUBLIC_COMPONENTS_ADDRESS=0xTokenComponents
NEXT_PUBLIC_MARKET_ADDRESS=0xTokenMarket
```

`NEXT_PUBLIC_*` values are intentionally visible. Private RPC keys, salts before launch and signer material must never use that prefix or enter Git.

## Verification gate

```bash
cd contracts
forge fmt --check
forge build
forge test --match-path test/TinyAITokenMode.t.sol -vv
forge test

cd ../web
pnpm lint
pnpm exec tsc --noEmit
pnpm build
```

The mainnet preflight must additionally prove:

1. the predicted token address is empty and ends in `7777`;
2. the live Portal's simulated return equals the predicted address;
3. `NVDAB` is still allowed as a quote token;
4. decoded launch calldata fixes `TinyAI` / `TINYAI`, the pinned metadata CID, `100` / `100` tax bps and `2,592,000` tax-duration seconds;
5. ordinary new-token transfers to Treasury are untaxed and settle exactly;
6. the Vault's immutable reward token is NVDAB and its bound Protocol matches the deployed Protocol;
7. the Flap TaxProcessor's market/beneficiary address is the Vault and real taxed trades increase Vault NVDAB balance;
8. a holder can claim NVDAB, a non-owner cannot claim, and rewards follow an AI transfer;
9. no signer, salt, RPC key or server secret appears in tracked files or build output.

Simulation, compilation and address mining do not broadcast a transaction. Every mainnet deployment or token-creation transaction still requires a fresh, transaction-specific authorization.
