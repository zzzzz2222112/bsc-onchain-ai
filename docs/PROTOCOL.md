# TinyAI Protocol Specification

## 1. Scope

This document specifies the state, actors and transitions of TinyAI Protocol. Normative language describes the reference Solidity implementation.

The protocol creates ownable AI state machines whose identity, brain selection, conversation history commitments, capabilities and market settlement live on an EVM chain.

## 2. Actors

| Actor | Authority |
| --- | --- |
| AI owner | Persist conversations, migrate the brain, configure automatic migration, seal the brain and fuse owned components |
| Registry owner | Publish brain engines, control new-migration eligibility and set a recommended version |
| Protocol owner | Rotate the primary-mint treasury |
| Component owner | Define and seal the genesis catalogue during initialization, rotate treasury and update metadata URI |
| Seller | List and cancel owned protocol assets and withdraw sale proceeds |
| Buyer | Purchase a valid listing at its exact native-asset price |

No actor may overwrite an existing brain version, exceed hard supply caps, change fixed primary prices or configure a market fee.

## 3. Protocol objects

### 3.1 AI

An AI is an ERC-721 token plus an `AIState` record. The token owner controls all state-writing lifecycle actions.

### 3.2 Brain

A brain is an `IBrainEngine` implementation published under a sequential registry version. It accepts bounded public AI context and returns deterministic inference output.

### 3.3 Component

A component is an ERC-1155 balance with an immutable effect definition and lifetime supply cap. Fusion burns the balance and changes AI state. The genesis metadata base URI is `ipfs://bafybeiduevofpggxdaxngsjfzyi4j5uvejtcwkffkh3hgoes6iuomptojm/{id}.json`.

### 3.4 Listing

A listing is a non-custodial offer for one AI or a quantity of one component ID. It becomes invalid when ownership, balance or approval no longer satisfies the market.

## 4. Fixed parameters

| Parameter | Genesis BNB mode | Flap Token Mode release candidate |
| --- | ---: | ---: |
| Maximum AI supply | 10,000 | 10,000 |
| AI mint price | 0.0001 BNB | 500 new Flap tokens |
| Genesis component lifetime supply | 100,000 | 100,000 |
| Component mint price | 0.0001 BNB per unit | 500 new Flap tokens per unit |
| Market protocol fee | 0 | 0 |
| Conversation protocol fee | 0 | 0 |
| Maximum prompt length | 280 bytes | 280 bytes |
| Initial memory capacity | 1 | 1 |
| Maximum memory capacity | 8 | 8 |
| Maximum additional response variants | 2 | 2 |

These values have no owner setter in their respective reference implementations. The Token Mode stack is predeployed on BSC mainnet and preconfigured against future Flap token address `0x30e892840E5E37083c986012934Bd845f8157777`. Because that address does not yet contain token runtime code, the stack MUST be described as predeployed rather than live production until the final token-creation transaction and post-launch verification complete.

## 5. AI creation

`mintAI(name, seed, autoUpgrade)` MUST:

1. reject minting after the 10,000-unit cap;
2. require a valid name and exact payment;
3. resolve an enabled recommended brain;
4. validate the brain through the registry;
5. derive a unique DNA commitment;
6. initialize bounded traits and one memory slot;
7. mint the ERC-721 to the caller; and
8. emit `AIBorn`.

The mint function has no per-wallet quota. Mint revenue remains in the protocol contract until withdrawal to the configured treasury.

## 6. Conversation transition

`chatAI(aiId, prompt)` MUST be called by the current ERC-721 owner. It accepts no native payment.

The transition MUST:

1. validate owner and prompt bounds;
2. apply an eligible automatic brain migration when enabled;
3. resolve the active engine through registry integrity checks;
4. execute inference with the current AI state;
5. commit the interaction to the memory ring;
6. advance turns and experience;
7. advance `memoryRoot`; and
8. emit `AIChat` with the public prompt, response and commitments.

A classified response adds three experience units. An unknown response adds one.

The contract exposes no public state-writing chat room and no public preview function. Read-only reproduction is possible by simulating the owner call with `eth_call`; simulation does not authorize or persist a transaction.

## 7. Memory model

The memory ring contains public interaction hashes. Its size is `memoryCapacity`, between one and eight.

A new interaction overwrites:

```text
slot = (turn - 1) mod memoryCapacity
```

The rolling `memoryRoot` commits to every persisted interaction, including those no longer individually present in the bounded ring.

Memory is public commitment state, not confidential storage.

## 8. Brain lifecycle

### 8.1 Publication

A new registry publication MUST:

- use the next sequential version;
- point to deployed runtime code;
- match the engine-reported version;
- pass engine integrity validation; and
- store the runtime code hash.

### 8.2 Resolution

Every inference resolution MUST recheck the stored runtime code hash and engine integrity.

### 8.3 Migration

An AI MAY migrate only to a higher version that is enabled for upgrades. Migration MAY be owner initiated or triggered by owner-enabled automatic migration.

### 8.4 Sealing

The AI owner MAY permanently seal the active brain. Sealing disables automatic migration and MUST be irreversible.

## 9. Component lifecycle

The genesis catalogue MUST be sealed at a combined lifetime cap of 100,000 units.

| ID | Component | Cap | Effect |
| ---: | --- | ---: | --- |
| 1 | Memory Cell | 30,000 | Memory capacity +1 |
| 2 | Curiosity Gene | 15,000 | Curiosity +5 |
| 3 | Empathy Gene | 15,000 | Empathy +5 |
| 4 | Humor Gene | 15,000 | Humor +5 |
| 5 | Caution Gene | 15,000 | Caution +5 |
| 6 | Expression Core | 10,000 | Additional deterministic variant +1 |

Public minting requires exact payment. There is no administrative mint path. Token Mode verifies the exact ERC-20 balance delta and rejects fee-on-transfer behavior, so an allowance alone cannot underpay the fixed 500-token amount.

Fusion MUST:

1. require AI ownership;
2. require a positive amount;
3. prove the complete effect remains within its bound;
4. burn the component through the bound protocol address;
5. apply the state change; and
6. emit `ComponentFused`.

Consumed components do not reopen lifetime mint capacity.

## 10. Market lifecycle

The market accepts only the configured AI and component contracts.

### 10.1 Listing

A seller MUST own the AI or hold the component balance and MUST grant transfer approval before listing.

### 10.2 Purchase

A purchase MUST:

- pay the exact listing amount;
- reject stale ownership, balance or approval;
- update listing and proceeds accounting before asset transfer;
- transfer the requested asset; and
- emit `Purchased`.

Component listings MAY be partially filled. AI listings always transfer one token.

### 10.3 Proceeds

Seller proceeds are credited to an internal `owed` balance and withdrawn separately. The market MUST NOT deduct a protocol fee.

## 11. Treasury flow

AI and component primary-mint revenue accumulates in the corresponding contracts. Withdrawal sends the full balance to the configured treasury.

The owner may rotate the treasury but cannot direct an individual withdrawal to an arbitrary address. Market proceeds are separate seller liabilities and never enter the primary-mint treasury path.

## 12. Integrity and observability

The protocol exposes public state and events sufficient to reconstruct:

- AI birth and current ownership;
- brain version and migration history;
- persistent conversation count and memory commitments;
- component issuance and fusion;
- listings, purchases, cancellations and proceeds withdrawals; and
- registry publication and recommendation changes.

A verifier SHOULD compare runtime bytecode hashes, registry records, transaction receipts and emitted events rather than relying on interface labels.

## 13. Governance boundary

Administrative authority is deliberately non-uniform.

- The registry owner can influence future brain availability.
- The protocol and component owners can rotate treasuries.
- The component owner can update metadata URI.
- AI owners control their own migration and sealing policy.
- The market has no owner.

Direct deployment avoids proxy-slot replacement, but governance keys remain security-critical. Production ownership SHOULD use publicly identified multisig or equivalent controls.

## 14. Canonical evidence

Public deployment records and runtime commitments are maintained under `contracts/deployments/`.

Those files are reproducibility aids. Current chain state, deployed bytecode and transaction receipts remain authoritative.
