# TinyAI Protocol

## Sovereign On-chain AI State Machines for the EVM

TinyAI Protocol is an EVM-native protocol for ownable, stateful and evolvable AI entities. Each AI is an ERC-721 identity bound to public memory commitments, bounded traits, capabilities and an explicitly selected brain engine. Inference and state transitions are executed by contracts and can be reproduced without the official website.

> TinyAI is defined by where execution happens and how state is controlled, not by a claim of human-level intelligence.

## Protocol thesis

Most blockchain-connected AI products keep the model, memory and final answer behind a private service. The chain records a payment or an NFT, but it cannot independently reproduce the intelligence path.

TinyAI uses a different boundary:

- the AI identity and lifecycle state live in EVM storage;
- brain releases are published through an append-only registry;
- engine bytecode and locked dependencies are checked before inference;
- supported retrieval and quantized generation execute inside the EVM;
- persistent conversations advance an AI-specific memory commitment;
- components are burned to change real protocol state; and
- ownership and market settlement are enforced by standard token interfaces.

Training may happen off-chain. Once a brain is published, the model data, execution route, final response and state transition are on-chain.

## Architecture

| Layer | Primitive | Responsibility |
| --- | --- | --- |
| Identity | `TinyAIProtocol` | ERC-721 ownership, DNA, traits, experience, memory, brain policy and component fusion |
| Brain publication | `TinyAIBrainRegistry` | Append-only versions, engine address, runtime code hash, upgrade eligibility and recommendation |
| Inference | `IBrainEngine` implementations | Deterministic routing, retrieval, quantized generation, fallback and trace commitment |
| Model storage | STOP-prefixed bytecode blobs | Immutable model matrices, dictionaries and UTF-8 lexicons addressable with `EXTCODECOPY` |
| Capabilities | `TinyAIComponents` | Capped ERC-1155 components burned to modify AI state |
| Settlement | `TinyAIMarket` | Non-custodial fixed-price sales and pull-payment proceeds |

### Execution path

```text
owner + aiId + prompt
          |
          v
  TinyAIProtocol
  ownership + AI state
          |
          v
 TinyAIBrainRegistry
 code hash + integrity
          |
          v
     Brain Engine
 routing + retrieval
 quantized generation
          |
          v
 response + traceHash
          |
          v
 turns + experience
 memoryRoot + memory ring
```

A persistent conversation follows one atomic state transition:

1. `TinyAIProtocol` proves that the caller owns the AI.
2. If the owner enabled automatic upgrades, the protocol resolves a newer recommended brain.
3. The registry rechecks the engine runtime code hash and `integrityOk()`.
4. The engine receives the prompt together with DNA, traits, capabilities, turn count and memory root.
5. The engine returns a response, topic, confidence, variant, unknown flag and `traceHash`.
6. The protocol commits the interaction into the public memory ring and advances experience and turn counters.
7. The complete prompt, response and resulting commitments are emitted as an event.

No oracle, relayer signature or private inference endpoint is part of this path.

## Deterministic on-chain inference

The reference brain combines three bounded systems:

- a sparse quantized semantic router;
- an authored fact retriever with explicit unknown handling; and
- an autoregressive int8 decoder for supported neural contexts.

The neural decoder uses 32 hidden units, a 133-token vocabulary, four deterministic variants and a maximum of 16 generated tokens. At every decoding step the EVM reconstructs the activation, scores the full vocabulary, selects the highest-scoring token and reads its UTF-8 bytes from an immutable lexicon blob.

The model and lexicon are not URLs. They are deployed bytecode payloads with fixed SHA-256 commitments. The engine locks its dependencies and verifies their runtime hashes. A supported output can therefore be reproduced from contract state and bytecode alone.

Unsupported inputs do not become invented facts. The retrieval layer may return a grounded bounded answer or an explicit unknown response.

## Ownable AI state

Every AI has an independent `AIState` record:

| Field | Meaning |
| --- | --- |
| `dna` | Deterministic identity seed created at mint |
| `memoryRoot` | Rolling commitment to every persisted interaction |
| `brainVersion` | Published engine version used for inference |
| `turns` / `experience` | Public progression counters |
| `curiosity`, `empathy`, `humor`, `caution` | Bounded behavioral traits |
| `memoryCapacity` | Queryable public memory ring size |
| `expressionLevel` | Number of additional deterministic variants |
| `skillMask` | Fused capability bits |
| `autoUpgrade` / `brainSealed` | Owner-controlled evolution policy |

Transferring the ERC-721 transfers control over this entire state machine. Only the current owner can persist a conversation, migrate the brain, change upgrade policy, seal the brain or fuse a component.

## Verifiable evolution

Brains are versioned, not replaced.

A registry publication stores the engine address, runtime code hash, publication time, label and upgrade eligibility. Versions are sequential and append-only. Historical engines remain addressable even when they stop accepting new migrations.

An AI owner can choose one of three policies:

- manually migrate to a higher enabled version;
- opt into the recommended version on the next persistent conversation; or
- irreversibly seal the current brain.

The registry owner can publish and recommend engines, but cannot silently rewrite an existing engine or force every AI to migrate.

## Components as state transitions

Genesis components are ERC-1155 assets with fixed meanings and lifetime caps. Fusion burns a component and changes the target AI's storage:

- Memory Cell increases the public memory ring capacity;
- personality genes increase bounded traits; and
- Expression Core unlocks an additional deterministic response variant.

A component cannot be consumed when its effect would be wasted. Burning does not reopen historical issuance capacity.

## Market settlement

`TinyAIMarket` supports the protocol's ERC-721 AI assets and ERC-1155 components.

Listings are non-custodial: the asset stays in the seller's wallet until purchase. The market checks ownership, balance and approval again at settlement, updates listing state before external transfers and supports partial component fills. In Token Mode, the exact ERC-20 purchase amount moves directly from buyer to seller in the same transaction. The separate Genesis BNB market retains its pull-payment proceeds balance.

The market has no owner and no fee-setting path. It provides deterministic settlement, not guaranteed liquidity.

## Hard protocol invariants

The currently deployed Genesis stack fixes the following properties in code:

- maximum AI supply: `10,000`;
- AI mint price: `0.0001 BNB`;
- Genesis component lifetime supply: `100,000`;
- component mint price: `0.0001 BNB`;
- market protocol fee: `0`;
- maximum prompt size: `280` bytes;
- maximum memory capacity: `8` slots;
- maximum additional expression variants: `2`;
- brain migration direction: higher enabled versions only; and
- brain sealing: irreversible.

Persistent conversation calls are non-payable. The AI owner pays normal network gas and no protocol chat fee.

The repository also contains the audited **Flap Token Mode release candidate**. It preserves the same supply, ownership, conversation and market invariants, but replaces native-BNB primary mint settlement with an exact ERC-20 payment:

- token name and symbol: `TinyAI` / `TINYAI`;
- official website and X account: `https://bnbtinyai.org` / `https://x.com/Tinyaipro`;
- immutable launch metadata CID: `QmcFiqZScoop6uDjpPzsxTuSkcEZGLs13iZjSHqFqhY2Qy` (avatar CID `Qmc1LroY5RzZCPzkmQK9oKDWWWaLHouUtbhhHEdahxX6Aq`);
- genesis component metadata URI: `ipfs://bafybeiduevofpggxdaxngsjfzyi4j5uvejtcwkffkh3hgoes6iuomptojm/{id}.json`;
- Flap buy tax and sell tax: `1%` each for `30 days` (`2,592,000` seconds) from launch;
- AI mint price: `500` newly created Flap tokens;
- component mint price: `500` newly created Flap tokens per unit;
- quote and AI-holder reward asset: BSC `NVDAB`;
- one owned AI represents one equal NVDAB reward share;
- market protocol fee and conversation protocol fee: `0`; and
- final Flap token creation and the Token Mode production deployment are **not yet live**.

The complete prelaunch specification and safe deployment order are documented in [ERC-20 Token Mode status](docs/TOKEN_MODE.md). Until its final deployment record exists, the BNB Genesis addresses below remain the canonical production stack. The website avatar is the exact public asset at [`web/public/tinyai-avatar.png`](web/public/tinyai-avatar.png).

## Trust and verification boundary

The protocol makes execution inspectable; it does not remove every trust assumption.

- Training data preparation and quantization occur off-chain.
- Published model identity does not prove model quality or factual completeness.
- Persistent prompts, responses, addresses and memory commitments are public.
- Registry governance controls which new brains may be published and recommended.
- Treasury governance controls the destination of primary mint revenue.
- Frontends and RPC providers are replaceable clients, not protocol authorities.
- Independent review is still required for production use.

A verifier can simulate `chatAI` with `eth_call` from the current owner address at a fixed block, compare the engine runtime hash with the registry commitment and repeat the call through another node. A real transaction can then be verified against the emitted `AIChat` event and the resulting memory state.

## Research horizon

TinyAI is a base protocol for long-lived on-chain intelligence, not a claim that the present model is the endpoint. The following directions describe future research, not deployed capabilities:

- **Larger deterministic brains:** sparse routing, bytecode-sharded parameters and bounded multi-stage decoding that increase useful capacity without surrendering replayability.
- **Hierarchical memory:** owner-controlled memory layers whose commitments remain public and whose retention rules can be verified independently of any interface.
- **Proof-carrying inference:** optional engines that combine execution with succinct proofs for workloads too large to reproduce directly inside one transaction, while clearly distinguishing proved computation from native EVM execution.
- **Open brain standards:** a common engine interface, immutable model commitments, reproducible build manifests and governance constraints that allow independently authored brains to compete without rewriting existing AI identities.
- **Agent composability:** consent-limited AI-to-AI coordination, programmable spending boundaries and contract-native capabilities built around explicit ownership rather than hidden service accounts.
- **Tokenized resources:** future fee and governance modules may coordinate scarce inference, storage or curation resources, but only through opt-in rules that remain visible at the contract layer.

The long-term objective is an AI object that can outlive a website, migrate between compatible applications and improve through transparent protocol upgrades while preserving its identity, ownership history and verifiable state continuity.

## Repository map

```text
contracts/src/protocol/   protocol, registry, components, market and brain engines
contracts/src/            classifier, retriever, generator, model card and bytecode blobs
contracts/test/           invariant, parity, ownership, market and gas-bound tests
model/                    training, quantization and frozen model artifacts
docs/                     protocol specification, architecture, security and whitepaper
web/                      replaceable reference client
```

The reference client is intentionally not part of the trust boundary. Any compatible application or contract can integrate the same public interfaces.

## BNB Smart Chain deployments

The table below records the separately deployed **Genesis BNB edition**. It remains independently verifiable and must not be mixed with Token Mode addresses. The principal executable contracts were source-verified on BscScan with Solidity `0.8.30`, 20,000 optimizer runs, `viaIR` enabled and the Cancun EVM target.

| Contract | Genesis mainnet address | Public source |
| --- | --- | --- |
| AI identity and state | [`0x5044...9c93`](https://bscscan.com/address/0x5044F577571dcA7cB7A0775aDcFa66E02bd49c93#code) | [`TinyAIProtocol.sol`](contracts/src/protocol/TinyAIProtocol.sol) |
| Components | [`0x9361...9bF1`](https://bscscan.com/address/0x936161FD89c4272f2B034f5414e6D9C7C9CB9bF1#code) | [`TinyAIComponents.sol`](contracts/src/protocol/TinyAIComponents.sol) |
| Native market | [`0x3dCB...e9b7`](https://bscscan.com/address/0x3dCBDB84bA220Cd9cA6E420b2bCe3D3610a1e9b7#code) | [`TinyAIMarket.sol`](contracts/src/protocol/TinyAIMarket.sol) |
| Brain registry | [`0x29Ee...1fA1`](https://bscscan.com/address/0x29EefCC07eA38535A16fe4fB9c9469d4634C1fA1#code) | [`TinyAIBrainRegistry.sol`](contracts/src/protocol/TinyAIBrainRegistry.sol) |
| Brain Engine V2 | [`0xE45F...DAb0`](https://bscscan.com/address/0xE45F1221EBaDb925062E1a706b16277943e7DAb0#code) | [`TinyAIBrainEngineV2.sol`](contracts/src/protocol/TinyAIBrainEngineV2.sol) |
| Neural Decoder V2 | [`0xe4D2...C7eF`](https://bscscan.com/address/0xe4D2944f722F2c8d685F3934FB2310321281C7eF#code) | [`TinyAINeuralDecoderV2.sol`](contracts/src/protocol/TinyAINeuralDecoderV2.sol) |

The [formal 45-transaction genesis record](contracts/deployments/bsc-mainnet-genesis.json), [Brain V2 release record](contracts/deployments/bsc-mainnet-brain-v2.json) and [source-verification registry](contracts/deployments/bsc-mainnet-source-verification.json) preserve transaction hashes, blocks, compiler settings and runtime code hashes. Token Mode will receive a separate production table only after its final token and contracts exist on BSC mainnet and pass reciprocal binding checks.

## Verification

```bash
cd contracts
forge install foundry-rs/forge-std@v1.16.2 --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 --no-git
forge test
forge fmt --check
```

```bash
cd web
pnpm lint
pnpm exec tsc --noEmit
pnpm build
```

Canonical public deployment evidence is stored under `contracts/deployments/`. Deployment artifacts are evidence, while the contracts and their live state remain the source of truth.

`scripts/prepare-source-verification.mjs` reconstructs exact Standard JSON compiler inputs from retained Foundry artifacts, recompiles them with the pinned `solc` binary and refuses to continue unless the resulting creation bytecode is a byte-for-byte prefix of the deployed transaction input. Explorer API keys, RPC credentials, signers and broadcast files remain outside this repository.

## Technical documents

- [Protocol specification](docs/PROTOCOL.md)
- [Execution architecture](docs/ARCHITECTURE.md)
- [Security and trust model](docs/SECURITY.md)
- [Reproducible deployment](docs/DEPLOYMENT.md)
- [ERC-20 Token Mode status](docs/TOKEN_MODE.md)
- [Whitepaper](docs/WHITEPAPER.md)

## Support protocol research

TinyAI is developed as open-source protocol research. Voluntary technical contributions can be sent on BNB Smart Chain:

- **Network:** BNB Smart Chain
- **Asset:** BNB
- **Address:** [`0x2d7E447136D57b9D6B5FcAACFc10F56c9E4Ebf25`](https://bscscan.com/address/0x2d7E447136D57b9D6B5FcAACFc10F56c9E4Ebf25)

Contributions support security review, reproducible model research, public infrastructure and open tooling. They are donations, not mint purchases, investments, governance rights or promises of financial return. Verify the network and address before sending; blockchain transfers are irreversible.

## License

MIT. Contract source, model tooling and generated artifacts in this repository are released under the same license.

## Maintainer

[`zzzzz2222112`](https://github.com/zzzzz2222112)
