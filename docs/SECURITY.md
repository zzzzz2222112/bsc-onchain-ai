# TinyAI Protocol Security and Trust Model

## 1. Security objectives

The reference implementation is designed to preserve these properties:

- only the current ERC-721 owner can mutate an AI;
- published brain versions are append-only;
- engine runtime identity is checked before inference;
- AI migration is monotonic and owner controlled;
- brain sealing is irreversible;
- AI and component supply caps cannot be increased;
- fixed primary prices have no administrative setter;
- component fusion cannot consume an asset without changing state;
- market assets remain non-custodial until purchase;
- seller proceeds are fully accounted through pull payments; and
- the market has no protocol-fee administration path.

## 2. Authority matrix

| Authority | Can | Cannot |
| --- | --- | --- |
| AI owner | Chat, migrate, configure auto-upgrade, fuse, seal and transfer | Rewrite a published engine or reverse sealing |
| Registry owner | Publish, recommend and control future migration eligibility | Replace an existing registry entry or force all AIs to migrate |
| Protocol owner | Rotate treasury | Change AI cap, mint price or owner-only chat rule |
| Component owner | Initialize and seal catalogue, rotate treasury, update URI | Admin-mint, change fixed price, exceed cap or reopen a sealed catalogue |
| Market | Settle approved protocol assets | Charge a fee, seize unapproved assets or list arbitrary collections |

Registry, protocol and component administration use two-step ownership transfer. The market has no owner role.

## 3. Integrity controls

### 3.1 Brain registry

Publication requires deployed runtime code, sequential versioning, matching engine version and successful engine integrity validation.

Resolution rechecks both `EXTCODEHASH` identity and `integrityOk()`. A dependency mismatch therefore fails closed before inference.

### 3.2 Immutable model dependencies

Reference brain engines lock the addresses and runtime hashes of their retriever, model and lexicon dependencies. Bytecode blobs begin with `STOP`, making their payload inert when called directly.

Fixed SHA-256 commitments protect the expected model and lexicon byte layouts.

### 3.3 Owner-only AI writes

`chatAI`, brain migration, policy changes, sealing and fusion resolve the live ERC-721 owner on-chain. Interface routing is a usability layer, not the authorization control.

### 3.4 Bounded computation

Prompt bytes, generated token count, trace shape, memory capacity, trait bounds and component effects are capped. Invalid or unsupported modules are rejected.

### 3.5 Settlement safety

Mint, component and market entry points use reentrancy protection where value or token transfer occurs. Market purchase logic updates listing and proceeds accounting before external transfers. Seller withdrawal follows pull-payment accounting.

## 4. Fund-flow boundaries

### Primary issuance

AI and component mint payments are held by their respective contracts. Withdrawal routes the complete balance to the configured treasury. Treasury rotation is administrative and must be monitored.

### Conversations

`chatAI` is non-payable. The protocol collects no conversation fee. The caller pays network gas directly to validators.

### Market

The buyer pays the exact listed amount. The complete amount is credited to the seller's `owed` balance. There is no fee recipient or fee-setting function.

## 5. External trust boundaries

### Training and knowledge

Training, corpus selection, fact authoring and quantization are off-chain processes. Hashes establish artifact identity, not correctness, neutrality or completeness.

### Governance keys

Registry and treasury administration are controlled by owner keys. Append-only publication limits retroactive mutation but does not eliminate governance risk for future releases or treasury rotation.

### Wallets

AI ownership authority is only as secure as the owner's signing environment. A compromised owner key can transfer the AI, change its migration policy, fuse components and persist public conversations.

### Frontends and RPC

A frontend can display misleading information or construct an unintended transaction. Wallet review and direct contract verification remain necessary.

RPC responses may be stale or censored. Fixed-block cross-provider checks reduce, but do not eliminate, infrastructure risk.

### Metadata

ERC-721 metadata is generated on-chain. ERC-1155 metadata URI remains administratively updateable and must not be treated as the component's authority; the on-chain component definition is authoritative.

## 6. Privacy model

TinyAI does not provide private inference.

Persistent prompts, responses, speaker addresses, brain versions, trace commitments and memory updates are public. Users must never submit private keys, passwords, seed phrases or confidential personal information.

The memory root is a commitment, not encryption. Individual ring-buffer entries are public hashes and may still reveal linkage and timing metadata.

## 7. Residual risks and non-goals

- A valid trace proves which deterministic path executed; it does not prove that the answer is factually correct.
- Model capacity is bounded and does not represent open-ended language understanding.
- A new brain may introduce new logic and requires independent review before owners opt in.
- Fixed supply does not create demand, liquidity or market value.
- Non-custodial listing does not guarantee sale or protect against user-approved malicious interfaces.
- Gas cost varies with route and state; a new engine must be tested against the target chain's current transaction limits.
- Chain reorganization, RPC inconsistency and ecosystem-level wallet risk remain outside the contracts.
- There is no formal verification proof or completed independent third-party audit at this time.

## 8. Verification checklist

A reviewer should verify:

1. deployed addresses and chain ID from transaction receipts;
2. source-to-bytecode correspondence;
3. registry owner, protocol owner, component owner and treasury;
4. each registry version's engine address and code hash;
5. engine dependency hashes and `integrityOk()`;
6. immutable AI and component caps and prices;
7. absence of a market fee or owner path;
8. owner-only rejection for every AI state mutation;
9. component catalogue sealing and lifetime counters;
10. market listing, partial fill, cancellation and withdrawal accounting; and
11. representative inference gas against the live chain limit.

## 9. Current engineering evidence

The repository contains 86 Foundry tests covering protocol invariants, ownership isolation, brain publication, deterministic output parity, dependency corruption, component effects, market accounting and gas bounds.

Frontend lint, static typing and production build are also verified. These checks are engineering evidence, not a substitute for independent audit.
