# TinyAI Protocol Architecture

## 1. Execution boundary

TinyAI Protocol treats an AI as a public state machine. The trusted execution boundary begins at the protocol contract and ends at the brain engine and its locked bytecode dependencies.

The following operations occur inside the EVM:

- ownership verification;
- brain version resolution;
- runtime code-hash validation;
- semantic routing and bounded retrieval;
- quantized generation for supported contexts;
- deterministic fallback selection;
- trace commitment construction;
- experience and turn updates;
- memory-root advancement; and
- component-driven state changes.

Training, corpus authoring and quantization occur off-chain. A frontend may prepare calls and display results, but it is not part of the inference boundary.

## 2. Contract graph

```text
                         +-----------------------+
                         | TinyAIBrainRegistry   |
                         | version -> engine     |
                         | codeHash + integrity  |
                         +-----------+-----------+
                                     |
                                     v
+-------------------+      +---------+----------+      +----------------------+
| TinyAIComponents  |----->| TinyAIProtocol     |----->| IBrainEngine         |
| ERC-1155          | burn | ERC-721 + AIState  |      | deterministic infer  |
| capped effects    |      | owner-only writes  |      +----------+-----------+
+-------------------+      +---------+----------+                 |
                                     |                            v
                                     |                 +----------+-----------+
                                     |                 | immutable model,     |
                                     |                 | retriever and lexicon|
                                     |                 +----------------------+
                                     v
                         +-----------+-----------+
                         | TinyAIMarket          |
                         | fixed-price settlement|
                         | pull-payment proceeds |
                         +-----------------------+
```

The graph deliberately separates identity, inference, capability supply and settlement. A new interface can replace the reference client without changing this graph.

## 3. AI state model

`TinyAIProtocol` is an enumerable ERC-721 collection. Each token ID maps to one `AIState`:

```solidity
struct AIState {
    bytes32 dna;
    bytes32 memoryRoot;
    uint64 bornAt;
    uint64 experience;
    uint32 brainVersion;
    uint32 turns;
    uint64 skillMask;
    uint8 memoryCapacity;
    uint8 curiosity;
    uint8 empathy;
    uint8 humor;
    uint8 caution;
    uint8 expressionLevel;
    bool autoUpgrade;
    bool brainSealed;
    bool publicChat; // reserved and always false
}
```

The ERC-721 owner is the write authority. State is transferred with the token because the state is indexed by token ID, not by wallet.

DNA is created from the protocol address, chain identifier, minter, token ID, user seed, previous block hash and name. It is an identity seed, not a secret or a source of unpredictable randomness.

## 4. Persistent inference lifecycle

`chatAI(aiId, prompt)` is the sole protocol conversation entry point. It is non-payable and owner-only.

### 4.1 Authorization

The protocol resolves `ownerOf(aiId)` and requires it to equal `msg.sender`. This rule is enforced by the contract rather than by the interface.

### 4.2 Optional brain migration

When `autoUpgrade` is enabled and the brain is not sealed, the protocol compares the AI's current version with the registry recommendation. A migration occurs only when the recommendation is higher, enabled for upgrades and passes registry integrity checks.

### 4.3 Engine resolution

`TinyAIBrainRegistry.engineFor(version)` checks:

1. the version exists;
2. the current engine runtime code hash equals the stored code hash; and
3. the engine still reports `integrityOk() == true`.

The registry returns the engine only after all checks pass.

### 4.4 Brain input

The engine receives public, bounded context:

- AI identifier and DNA;
- four personality traits;
- expression level and skill mask;
- turn count and memory root;
- speaker address; and
- prompt bytes.

The prompt is non-empty and limited to 280 bytes.

### 4.5 Brain output

Every engine conforms to `IBrainEngine` and returns:

- response bytes;
- confidence;
- topic;
- response variant;
- unknown flag;
- neural-generation flag; and
- trace hash.

The trace hash is an integrity commitment to the selected modules, AI context and execution route. It is not a hidden chain-of-thought representation.

### 4.6 State commitment

For turn `n`, the protocol computes:

```text
interactionHash_n =
  H(memoryRoot_(n-1),
    speaker,
    H(prompt),
    H(response),
    traceHash,
    blockNumber)

slot_n = (n - 1) mod memoryCapacity

memoryRoot_n =
  H(memoryRoot_(n-1), interactionHash_n, slot_n, n)
```

It then updates the ring slot, turn count, experience and memory root before emitting `AIChat`.

An `eth_call` simulation from the current owner address executes the same bytecode without persisting state. A signed transaction performs the state transition.

## 5. Model and inference architecture

The reference inference stack is hybrid and bounded.

### 5.1 Sparse semantic routing

The classifier decodes bounded UTF-8 input, emits hashed lexical features, binary-searches a collision-checked dictionary and accumulates quantized intent and sentiment scores. Unknown features are ignored rather than mapped into an uncontrolled bucket.

### 5.2 Grounded retrieval

The retriever combines trained topic scores with explicit entity, cue and negation parsing. It returns bounded fact identifiers and can choose an unknown path when the evidence threshold is not met.

### 5.3 Quantized neural decoding

For supported contexts, the neural decoder performs autoregressive int8 inference:

- 6 semantic contexts;
- 4 deterministic variants;
- 32 hidden units;
- 133 vocabulary tokens;
- maximum 16 generated tokens;
- complete vocabulary scoring at every step; and
- greedy argmax token selection.

Model matrices and UTF-8 lexicon data are stored in immutable STOP-prefixed bytecode blobs. The decoder reads payloads with code-copy operations and checks fixed SHA-256 commitments.

### 5.4 Deterministic fallback

Inputs outside the supported neural route retain the grounded retriever output or an explicit unknown response. The protocol does not convert missing knowledge into an unverified universal answer.

## 6. Brain publication

The registry is append-only. Publication requires a deployed engine whose reported version is exactly the next registry version and whose integrity check succeeds.

A publication records:

- engine address;
- engine runtime code hash;
- publication timestamp;
- label; and
- whether the version accepts new migrations.

The registry owner may publish, recommend and disable a version as a new migration destination. Existing entries cannot be overwritten, and disabling migration does not destroy historical execution.

AI owners retain the final lifecycle choice: manual migration, opt-in automatic migration or irreversible sealing.

## 7. Component execution

`TinyAIComponents` is a capped ERC-1155 catalogue. Each component definition fixes an effect kind, target slot, power and lifetime cap.

The component contract is bound to the protocol once. Only the protocol can consume components, and consumption occurs only after checking that the effect changes state. A successful fusion burns the component and updates memory capacity, personality, expression range or a skill bit in the same transaction.

## 8. Market execution

`TinyAIMarket` supports only the configured AI and component contracts.

A listing records the seller, asset, token ID, remaining amount and unit price. Assets remain in the seller's wallet. Purchase-time ownership, balance and approval checks invalidate stale offers.

Settlement follows checks-effects-interactions:

1. validate exact payment;
2. update or delete the listing;
3. credit seller proceeds;
4. transfer the asset; and
5. let the seller withdraw through a separate pull-payment call.

The market has no administrative role and no fee configuration.

## 9. Resource bounds

The protocol limits prompt size, generated token count, memory capacity, component effects and brain interface output. These bounds make gas consumption and state growth analyzable.

Gas cost is an execution constraint, not a measure of intelligence. Every new brain must independently satisfy the target chain's transaction gas limit and preserve deterministic output under the protocol interface.

## 10. Replaceable infrastructure

The following systems are outside the protocol authority:

- websites and mobile clients;
- RPC providers and indexers;
- metadata gateways;
- analytics services; and
- block explorers.

They can improve access and discovery but cannot change contract state without a valid transaction. Independent verification should use fixed block numbers and, where practical, more than one RPC provider.
