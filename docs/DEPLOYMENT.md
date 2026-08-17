# Reproducible Protocol Deployment

## 1. Purpose

This document describes a reproducible release process for TinyAI Protocol. It separates build evidence, local simulation, signing and public-chain broadcast.

A successful build or simulation is not transaction authorization.

## 2. Release artifacts

A complete release consists of:

- Solidity source and pinned dependencies;
- frozen classifier, retriever, model and lexicon artifacts;
- model and lexicon commitments;
- compiler and optimizer settings;
- ordered contract-creation inputs;
- predicted addresses;
- owner and treasury configuration;
- per-transaction gas limits and maximum native-asset budget;
- expected runtime bytecode hashes; and
- a post-deployment audit record.

Generated secrets, keystores, passwords, RPC credentials and wallet configuration must remain outside the repository.

## 3. Build verification

From the repository root:

```bash
cd contracts
forge fmt --check
forge build
forge test
```

The release must fail if generated model artifacts drift from their committed hashes or if any runtime exceeds the target EVM code-size limit.

The reference client is verified separately:

```bash
cd web
pnpm install --frozen-lockfile
pnpm lint
pnpm exec tsc --noEmit
pnpm build
```

The client build is not part of contract correctness, but it must encode the canonical chain and contract addresses accurately.

## 4. Deployment order

The reference stack is created in dependency order:

1. immutable model and lexicon bytecode blobs;
2. model card and semantic classifier;
3. knowledge and retrieval modules;
4. quantized generator or decoder;
5. brain engine;
6. append-only brain registry;
7. capped component collection;
8. ERC-721 AI protocol;
9. protocol-only market;
10. component binding and catalogue sealing; and
11. ownership-transfer initiation when final governance differs from the deployer.

Each dependent contract must lock and validate the addresses and runtime hashes it relies on.

## 5. Configuration boundary

The release manifest must identify:

- target chain ID;
- deployer address;
- final registry, protocol and component owner;
- treasury address;
- component metadata URI;
- exact compiler profile;
- starting nonce;
- expected transaction count;
- native value per transaction; and
- maximum total gas budget.

Addresses are public configuration. Private keys and RPC credentials are not configuration values for publication.

Use an encrypted keystore or hardware-backed signer. Never place a raw private key in an environment file, command line, shell history, log or broadcast artifact.

## 6. Preflight

Before signing:

1. rebuild from a clean dependency state;
2. regenerate and compare every model commitment;
3. run all contract tests and size checks;
4. execute the complete deployment plan on an isolated chain using the target chain ID;
5. verify creation order, nonces, predicted addresses and constructor arguments;
6. compare every simulated runtime hash with the manifest;
7. simulate protocol mint, owner-only chat, migration, sealing, fusion and market settlement;
8. refresh gas price, chain gas limit and deployer balance; and
9. produce a final transaction-by-transaction manifest for review.

The preflight environment must not share an unlocked account with a public RPC endpoint.

## 7. Broadcast

Broadcast must use the exact reviewed manifest. Any change to chain ID, sender, nonce, calldata, constructor argument, native value, gas limit, recipient or maximum budget invalidates the previous approval.

Transactions should be submitted serially and reconciled by nonce. A failed or missing receipt must stop the release until the resulting state is understood.

## 8. Initialization verification

After creation:

- confirm every receipt succeeded;
- verify every deployed runtime code hash;
- verify registry publication order and recommendation;
- verify component definitions sum to the fixed lifetime cap;
- verify the catalogue is sealed;
- verify the component contract is bound to the intended protocol;
- verify AI and component fixed prices and caps;
- verify market assets and zero-fee behavior;
- verify owner and treasury addresses; and
- complete any two-step ownership acceptance.

No interface should be published before these checks pass.

## 9. Inference verification

A production release should verify at least one supported and one unsupported prompt.

For each case:

1. resolve the AI's brain version;
2. compare engine runtime hash with the registry;
3. simulate `chatAI` from the owner at a fixed block;
4. estimate gas against the live transaction limit;
5. submit an explicitly approved owner transaction;
6. verify `AIChat`, response bytes and trace hash; and
7. verify turns, experience, memory root and ring slot.

## 10. Source publication

Source verification must use the exact standard JSON compiler input and constructor arguments that produced the deployed bytecode.

Raw STOP-prefixed model blobs are data-bearing runtime code. They should be verified through payload commitments and runtime code hashes rather than represented as ordinary Solidity contracts.

## 11. Client configuration

Public client configuration may include chain ID, explorer URL, contract addresses, deployment start block and repository URL.

Server-only RPC credentials must never use a `NEXT_PUBLIC_` variable or appear in committed files. Wallet-facing RPC URLs must not contain provider API keys.

The official interface is replaceable and cannot substitute for contract verification.

## 12. Canonical records

The repository stores public release evidence under `contracts/deployments/`.

A canonical record should contain chain ID, addresses, transaction hashes, block numbers, runtime code hashes, gas used and post-deployment integrity checks. It must contain no secret material.
