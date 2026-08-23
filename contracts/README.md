# Contracts

The Foundry package deploys 26 contracts for the fee-free core: twenty-two immutable sparse-model chunks, two answer lexicons, one model card, and one chat engine. The bundled-token mode adds one fixed-supply token.

```bash
forge install foundry-rs/forge-std@v1.16.2 --no-commit
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 --no-commit
forge fmt --check
forge test
forge build --sizes
forge lint
slither . --exclude-dependencies --filter-paths "lib/"
```

`script/Deploy.s.sol` reads model artifacts from `../model/build`. It only broadcasts when the caller explicitly supplies Foundry's `--broadcast` flag.

Configuration is listed in `.env.example`. For an external payment token, set `DEPLOY_TOKEN=false` and `PAYMENT_TOKEN`; the token must support ordinary `transferFrom`, and `chatWithPermit` additionally requires EIP-2612. The plain `chat` path remains available for prior allowance.

For mainnet, prefer `CLI_SIGNER=true` with Foundry's `--keystore` and `--password-file` options so no raw private key is placed in the project or process environment. `--unlocked` is reserved for the local Anvil account. The legacy `DEPLOYER_PRIVATE_KEY` branch remains available for isolated tooling, but it is not the recommended production path.

`Deploy.s.sol` deploys a complete model version. `DeployPaidChat.s.sol` takes an existing verified `MODEL_CARD` and deploys only the payment token (or accepts `PAYMENT_TOKEN`) plus a paid `TinyAIChat`. This is the intended cost-saving upgrade path: the 22 weight blobs and two response lexicons are never duplicated.

## Flap Token Mode release candidate

Token Mode is a separate deployment path for a future Flap Tax Token V3. AI and component minting each require an exact `500e18` token payment, while chat, brain upgrades and the secondary-market protocol fee remain zero. The quote and AI-holder reward asset is pinned to BSC NVDAB.

The required order is:

1. mine the deterministic Flap salt with `web/scripts/mine-flap-salt.mjs` and keep the salt outside the Git worktree;
2. lock that salt to Token V3 with `LockFlapSaltForTinyAI.s.sol` through a protected submission path;
3. deploy `TinyAIHolderVault` and the complete token-settled protocol stack against the predicted token address; and
4. only after reciprocal binding checks pass, create the Flap token with `CreateFlapTokenForTinyAI.s.sol`.

None of these scripts broadcasts unless `--broadcast` is explicitly supplied. The release candidate is not a production deployment until the final token creation and live-chain verification records are published. See `../docs/TOKEN_MODE.md` for the full invariant and validation checklist.

Every data blob starts with `STOP`, so an accidental call returns immediately instead of executing model bytes as opcodes. There is no proxy, owner, pause, blacklist, fee setter, model setter, treasury setter, or post-deploy mint function. A new model requires a new deployment.
