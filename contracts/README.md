# Contracts

The Foundry package contains both the original fee-free chat core and the current lifecycle protocol. The formal BSC protocol release uses 36 contract creations plus nine initialization calls: immutable model and lexicon storage, retrieval and generation modules, a versioned brain registry, ERC-721 AI state, capped ERC-1155 components and a native settlement market.

```bash
forge install foundry-rs/forge-std@v1.16.2 --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 --no-git
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

Every data blob starts with `STOP`, so an accidental call returns immediately instead of executing model bytes as opcodes. There is no proxy, owner, pause, blacklist, fee setter, model setter, treasury setter, or post-deploy mint function. A new model requires a new deployment.
