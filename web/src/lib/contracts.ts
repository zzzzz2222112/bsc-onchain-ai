export const chatAbi = [
  {
    type: "function", name: "preview", stateMutability: "view",
    inputs: [{ name: "user", type: "address" }, { name: "prompt", type: "string" }],
    outputs: [{ name: "result", type: "tuple", components: [
      { name: "response", type: "string" }, { name: "intent", type: "uint8" },
      { name: "secondaryIntent", type: "uint8" },
      { name: "sentiment", type: "uint8" }, { name: "nextMood", type: "int8" },
      { name: "confidence", type: "uint16" }, { name: "variant", type: "uint8" },
      { name: "nextContext", type: "bytes32" }, { name: "chinese", type: "bool" },
      { name: "followedContext", type: "bool" },
    ] }],
  },
  {
    type: "function", name: "chat", stateMutability: "nonpayable",
    inputs: [{ name: "prompt", type: "string" }],
    outputs: [{ name: "result", type: "tuple", components: [
      { name: "response", type: "string" }, { name: "intent", type: "uint8" },
      { name: "secondaryIntent", type: "uint8" },
      { name: "sentiment", type: "uint8" }, { name: "nextMood", type: "int8" },
      { name: "confidence", type: "uint16" }, { name: "variant", type: "uint8" },
      { name: "nextContext", type: "bytes32" }, { name: "chinese", type: "bool" },
      { name: "followedContext", type: "bool" },
    ] }],
  },
  {
    type: "function", name: "chatWithPermit", stateMutability: "nonpayable",
    inputs: [
      { name: "prompt", type: "string" }, { name: "deadline", type: "uint256" },
      { name: "v", type: "uint8" }, { name: "r", type: "bytes32" }, { name: "s", type: "bytes32" },
    ],
    outputs: [{ name: "result", type: "tuple", components: [
      { name: "response", type: "string" }, { name: "intent", type: "uint8" },
      { name: "secondaryIntent", type: "uint8" },
      { name: "sentiment", type: "uint8" }, { name: "nextMood", type: "int8" },
      { name: "confidence", type: "uint16" }, { name: "variant", type: "uint8" },
      { name: "nextContext", type: "bytes32" }, { name: "chinese", type: "bool" },
      { name: "followedContext", type: "bool" },
    ] }],
  },
  {
    type: "function", name: "memoryOf", stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "memory", type: "tuple", components: [
      { name: "turns", type: "uint32" }, { name: "lastIntent", type: "uint8" },
      { name: "mood", type: "int8" }, { name: "confidence", type: "uint16" },
      { name: "rollingContext", type: "bytes32" },
    ] }],
  },
  { type: "function", name: "VERSION", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "feePerChat", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "burnBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "treasury", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "paymentToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "modelCard", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "totalChats", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  {
    type: "event", name: "Chat", inputs: [
      { name: "user", type: "address", indexed: true }, { name: "turn", type: "uint32", indexed: true },
      { name: "intent", type: "uint8", indexed: true }, { name: "secondaryIntent", type: "uint8", indexed: false },
      { name: "sentiment", type: "uint8", indexed: false },
      { name: "mood", type: "int8", indexed: false }, { name: "confidence", type: "uint16", indexed: false },
      { name: "variant", type: "uint8", indexed: false }, { name: "feePaid", type: "uint256", indexed: false },
      { name: "prompt", type: "string", indexed: false }, { name: "response", type: "string", indexed: false },
      { name: "contextHash", type: "bytes32", indexed: false },
      { name: "followedContext", type: "bool", indexed: false },
    ],
  },
] as const;

export const reasonerV4Abi = [
  {
    type: "function", name: "preview", stateMutability: "view",
    inputs: [
      { name: "user", type: "address" },
      { name: "prompt", type: "string" },
      { name: "depth", type: "uint8" },
    ],
    outputs: [{ name: "result", type: "tuple", components: [
      { name: "response", type: "string" }, { name: "domain", type: "uint8" },
      { name: "queryType", type: "uint8" }, { name: "confidence", type: "uint16" },
      { name: "depth", type: "uint8" }, { name: "stepCount", type: "uint8" },
      { name: "facts", type: "uint64" }, { name: "conclusions", type: "uint64" },
      { name: "traceHash", type: "bytes32" }, { name: "nextContext", type: "bytes32" },
      { name: "chinese", type: "bool" }, { name: "followedContext", type: "bool" },
      { name: "trace", type: "bytes32[12]" },
    ] }],
  },
  {
    type: "function", name: "chat", stateMutability: "nonpayable",
    inputs: [{ name: "prompt", type: "string" }, { name: "depth", type: "uint8" }],
    outputs: [{ name: "result", type: "tuple", components: [
      { name: "response", type: "string" }, { name: "domain", type: "uint8" },
      { name: "queryType", type: "uint8" }, { name: "confidence", type: "uint16" },
      { name: "depth", type: "uint8" }, { name: "stepCount", type: "uint8" },
      { name: "facts", type: "uint64" }, { name: "conclusions", type: "uint64" },
      { name: "traceHash", type: "bytes32" }, { name: "nextContext", type: "bytes32" },
      { name: "chinese", type: "bool" }, { name: "followedContext", type: "bool" },
      { name: "trace", type: "bytes32[12]" },
    ] }],
  },
  {
    type: "function", name: "memoryOf", stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "memory", type: "tuple", components: [
      { name: "turns", type: "uint32" }, { name: "lastDomain", type: "uint8" },
      { name: "lastQuery", type: "uint8" }, { name: "confidence", type: "uint16" },
      { name: "rollingContext", type: "bytes32" },
    ] }],
  },
  { type: "function", name: "VERSION", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "RULE_COUNT", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "MAX_TRACE_STEPS", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "KNOWLEDGE_HASH", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "knowledgeCodeHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "knowledge", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "integrityOk", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "totalChats", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "architecture", stateMutability: "pure", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "truthBoundary", stateMutability: "pure", inputs: [], outputs: [{ type: "string" }] },
  {
    type: "event", name: "ReasonedChat", inputs: [
      { name: "user", type: "address", indexed: true }, { name: "turn", type: "uint32", indexed: true },
      { name: "domain", type: "uint8", indexed: true }, { name: "queryType", type: "uint8", indexed: false },
      { name: "confidence", type: "uint16", indexed: false }, { name: "depth", type: "uint8", indexed: false },
      { name: "stepCount", type: "uint8", indexed: false }, { name: "facts", type: "uint64", indexed: false },
      { name: "conclusions", type: "uint64", indexed: false }, { name: "prompt", type: "string", indexed: false },
      { name: "response", type: "string", indexed: false }, { name: "traceHash", type: "bytes32", indexed: false },
      { name: "contextHash", type: "bytes32", indexed: false }, { name: "followedContext", type: "bool", indexed: false },
      { name: "trace", type: "bytes32[12]", indexed: false },
    ],
  },
] as const;

export const retrieverV5Abi = [
  {
    type: "function", name: "preview", stateMutability: "view",
    inputs: [{ name: "user", type: "address" }, { name: "prompt", type: "string" }],
    outputs: [{ name: "result", type: "tuple", components: [
      { name: "response", type: "string" }, { name: "evidence", type: "string" },
      { name: "intent", type: "uint8" }, { name: "secondaryIntent", type: "uint8" },
      { name: "topic", type: "uint8" }, { name: "queryType", type: "uint8" },
      { name: "classifierConfidence", type: "uint16" }, { name: "matchScore", type: "uint16" },
      { name: "cues", type: "uint64" }, { name: "factIds", type: "uint16[3]" },
      { name: "factCount", type: "uint8" }, { name: "unknown", type: "bool" },
      { name: "negated", type: "bool" }, { name: "chinese", type: "bool" },
      { name: "followedContext", type: "bool" }, { name: "traceHash", type: "bytes32" },
      { name: "nextContext", type: "bytes32" }, { name: "trace", type: "bytes32[5]" },
    ] }],
  },
  {
    type: "function", name: "chat", stateMutability: "nonpayable",
    inputs: [{ name: "prompt", type: "string" }],
    outputs: [{ name: "result", type: "tuple", components: [
      { name: "response", type: "string" }, { name: "evidence", type: "string" },
      { name: "intent", type: "uint8" }, { name: "secondaryIntent", type: "uint8" },
      { name: "topic", type: "uint8" }, { name: "queryType", type: "uint8" },
      { name: "classifierConfidence", type: "uint16" }, { name: "matchScore", type: "uint16" },
      { name: "cues", type: "uint64" }, { name: "factIds", type: "uint16[3]" },
      { name: "factCount", type: "uint8" }, { name: "unknown", type: "bool" },
      { name: "negated", type: "bool" }, { name: "chinese", type: "bool" },
      { name: "followedContext", type: "bool" }, { name: "traceHash", type: "bytes32" },
      { name: "nextContext", type: "bytes32" }, { name: "trace", type: "bytes32[5]" },
    ] }],
  },
  {
    type: "function", name: "memoryOf", stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "memory", type: "tuple", components: [
      { name: "turns", type: "uint32" }, { name: "lastTopic", type: "uint8" },
      { name: "lastIntent", type: "uint8" }, { name: "matchScore", type: "uint16" },
      { name: "rollingContext", type: "bytes32" },
    ] }],
  },
  { type: "function", name: "VERSION", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "MAX_FACTS", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "KNOWLEDGE_HASH", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "classifier", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "modelCard", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "knowledge", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "classifierCodeHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "modelCardCodeHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "knowledgeCodeHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "integrityOk", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "totalChats", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "architecture", stateMutability: "pure", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "truthBoundary", stateMutability: "pure", inputs: [], outputs: [{ type: "string" }] },
  {
    type: "event", name: "RetrievedChat", inputs: [
      { name: "user", type: "address", indexed: true }, { name: "turn", type: "uint32", indexed: true },
      { name: "topic", type: "uint8", indexed: true }, { name: "intent", type: "uint8", indexed: false },
      { name: "queryType", type: "uint8", indexed: false },
      { name: "classifierConfidence", type: "uint16", indexed: false },
      { name: "matchScore", type: "uint16", indexed: false }, { name: "cues", type: "uint64", indexed: false },
      { name: "factIds", type: "uint16[3]", indexed: false }, { name: "factCount", type: "uint8", indexed: false },
      { name: "unknown", type: "bool", indexed: false }, { name: "negated", type: "bool", indexed: false },
      { name: "prompt", type: "string", indexed: false }, { name: "response", type: "string", indexed: false },
      { name: "evidence", type: "string", indexed: false }, { name: "traceHash", type: "bytes32", indexed: false },
      { name: "contextHash", type: "bytes32", indexed: false },
    ],
  },
] as const;

const generatorV6Result = [
  { name: "response", type: "string" }, { name: "evidence", type: "string" },
  { name: "topic", type: "uint8" }, { name: "queryType", type: "uint8" },
  { name: "neuralContext", type: "uint8" }, { name: "variant", type: "uint8" },
  { name: "tokenCount", type: "uint8" }, { name: "stepCount", type: "uint8" },
  { name: "tokenIds", type: "uint8[16]" }, { name: "tokenScores", type: "int32[16]" },
  { name: "classifierConfidence", type: "uint16" }, { name: "matchScore", type: "uint16" },
  { name: "factIds", type: "uint16[3]" }, { name: "factCount", type: "uint8" },
  { name: "neuralGenerated", type: "bool" }, { name: "unknown", type: "bool" },
  { name: "negated", type: "bool" }, { name: "retrievalTraceHash", type: "bytes32" },
  { name: "generationTraceHash", type: "bytes32" }, { name: "nextContext", type: "bytes32" },
] as const;

export const generatorV6Abi = [
  {
    type: "function", name: "preview", stateMutability: "view",
    inputs: [{ name: "user", type: "address" }, { name: "prompt", type: "string" }],
    outputs: [{ name: "result", type: "tuple", components: generatorV6Result }],
  },
  {
    type: "function", name: "chat", stateMutability: "nonpayable",
    inputs: [{ name: "prompt", type: "string" }],
    outputs: [{ name: "result", type: "tuple", components: generatorV6Result }],
  },
  {
    type: "function", name: "memoryOf", stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "memory", type: "tuple", components: [
      { name: "turns", type: "uint32" }, { name: "lastTopic", type: "uint8" },
      { name: "lastNeuralContext", type: "uint8" }, { name: "lastTokenCount", type: "uint8" },
      { name: "rollingContext", type: "bytes32" },
    ] }],
  },
  { type: "function", name: "VERSION", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "NEURAL_CONTEXTS", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "VARIANTS", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "VOCABULARY_TOKENS", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "HIDDEN_UNITS", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "MODEL_BYTES", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "LEXICON_BYTES", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "MODEL_SHA256", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "LEXICON_SHA256", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "CORPUS_SHA256", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "retriever", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "modelBlob", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "lexiconBlob", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "retrieverCodeHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "modelCodeHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "lexiconCodeHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "integrityOk", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "totalChats", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "architecture", stateMutability: "pure", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "truthBoundary", stateMutability: "pure", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "capacityBoundary", stateMutability: "pure", inputs: [], outputs: [{ type: "string" }] },
  {
    type: "event", name: "GeneratedChat", inputs: [
      { name: "user", type: "address", indexed: true }, { name: "turn", type: "uint32", indexed: true },
      { name: "topic", type: "uint8", indexed: true }, { name: "neuralContext", type: "uint8", indexed: false },
      { name: "variant", type: "uint8", indexed: false }, { name: "tokenCount", type: "uint8", indexed: false },
      { name: "stepCount", type: "uint8", indexed: false }, { name: "tokenIds", type: "uint8[16]", indexed: false },
      { name: "tokenScores", type: "int32[16]", indexed: false }, { name: "factIds", type: "uint16[3]", indexed: false },
      { name: "factCount", type: "uint8", indexed: false }, { name: "neuralGenerated", type: "bool", indexed: false },
      { name: "unknown", type: "bool", indexed: false }, { name: "prompt", type: "string", indexed: false },
      { name: "response", type: "string", indexed: false }, { name: "evidence", type: "string", indexed: false },
      { name: "retrievalTraceHash", type: "bytes32", indexed: false },
      { name: "generationTraceHash", type: "bytes32", indexed: false },
      { name: "contextHash", type: "bytes32", indexed: false },
    ],
  },
] as const;

export const modelCardAbi = [
  { type: "function", name: "MODEL_CHUNK_COUNT", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "MODEL_BYTES", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "ACTIVE_FEATURES", stateMutability: "view", inputs: [], outputs: [{ type: "uint32" }] },
  { type: "function", name: "weightsBlobs", stateMutability: "view", inputs: [{ name: "index", type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "zhLexiconBlob", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "enLexiconBlob", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "weightsCodeHashes", stateMutability: "view", inputs: [{ name: "index", type: "uint256" }], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "zhLexiconCodeHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "enLexiconCodeHash", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "corpusSha256", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "publishedAt", stateMutability: "pure", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "integrityOk", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
] as const;

export const tokenAbi = [
  { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "nonces", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "value", type: "uint256" }], outputs: [{ type: "bool" }] },
] as const;

const brainOutput = [
  { name: "response", type: "string" }, { name: "confidence", type: "uint16" },
  { name: "topic", type: "uint8" }, { name: "variant", type: "uint8" },
  { name: "unknown", type: "bool" }, { name: "neuralGenerated", type: "bool" },
  { name: "traceHash", type: "bytes32" },
] as const;

const aiState = [
  { name: "dna", type: "bytes32" }, { name: "memoryRoot", type: "bytes32" },
  { name: "bornAt", type: "uint64" }, { name: "experience", type: "uint64" },
  { name: "brainVersion", type: "uint32" }, { name: "turns", type: "uint32" },
  { name: "skillMask", type: "uint64" }, { name: "memoryCapacity", type: "uint8" },
  { name: "curiosity", type: "uint8" }, { name: "empathy", type: "uint8" },
  { name: "humor", type: "uint8" }, { name: "caution", type: "uint8" },
  { name: "expressionLevel", type: "uint8" }, { name: "autoUpgrade", type: "bool" },
  { name: "brainSealed", type: "bool" }, { name: "publicChat", type: "bool" },
] as const;

export const protocolAbi = [
  { type: "function", name: "totalSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "nextAIId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "MAX_AI_SUPPLY", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "mintPrice", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "CHAT_PRICE", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "paymentToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "holderVault", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "tokenOfOwnerByIndex", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "index", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "tokensOfOwner", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256[]" }] },
  { type: "function", name: "ownerOf", stateMutability: "view", inputs: [{ name: "aiId", type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "getApproved", stateMutability: "view", inputs: [{ name: "aiId", type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "isApprovedForAll", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "operator", type: "address" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "operator", type: "address" }, { name: "aiId", type: "uint256" }], outputs: [] },
  { type: "function", name: "aiName", stateMutability: "view", inputs: [{ name: "aiId", type: "uint256" }], outputs: [{ type: "string" }] },
  { type: "function", name: "aiState", stateMutability: "view", inputs: [{ name: "aiId", type: "uint256" }], outputs: [{ name: "state", type: "tuple", components: aiState }] },
  { type: "function", name: "memoryAt", stateMutability: "view", inputs: [{ name: "aiId", type: "uint256" }, { name: "slot", type: "uint8" }], outputs: [{ type: "bytes32" }] },
  {
    type: "function", name: "mintAI", stateMutability: "payable",
    inputs: [{ name: "name", type: "string" }, { name: "seed", type: "bytes32" }, { name: "autoUpgrade", type: "bool" }],
    outputs: [{ name: "aiId", type: "uint256" }],
  },
  {
    type: "function", name: "chatAI", stateMutability: "nonpayable",
    inputs: [{ name: "aiId", type: "uint256" }, { name: "prompt", type: "string" }],
    outputs: [{ name: "output", type: "tuple", components: brainOutput }],
  },
  { type: "function", name: "upgradeBrain", stateMutability: "nonpayable", inputs: [{ name: "aiId", type: "uint256" }, { name: "nextVersion", type: "uint32" }], outputs: [] },
  { type: "function", name: "setAutoUpgrade", stateMutability: "nonpayable", inputs: [{ name: "aiId", type: "uint256" }, { name: "enabled", type: "bool" }], outputs: [] },
  { type: "function", name: "sealBrain", stateMutability: "nonpayable", inputs: [{ name: "aiId", type: "uint256" }], outputs: [] },
  { type: "function", name: "fuseComponent", stateMutability: "nonpayable", inputs: [{ name: "aiId", type: "uint256" }, { name: "componentId", type: "uint256" }, { name: "amount", type: "uint64" }], outputs: [] },
  {
    type: "event", name: "AIBorn", inputs: [
      { name: "aiId", type: "uint256", indexed: true }, { name: "owner", type: "address", indexed: true },
      { name: "brainVersion", type: "uint32", indexed: true }, { name: "dna", type: "bytes32", indexed: false },
      { name: "name", type: "string", indexed: false }, { name: "autoUpgrade", type: "bool", indexed: false },
    ],
  },
  {
    type: "event", name: "AIChat", inputs: [
      { name: "aiId", type: "uint256", indexed: true }, { name: "speaker", type: "address", indexed: true },
      { name: "turn", type: "uint32", indexed: true }, { name: "brainVersion", type: "uint32", indexed: false },
      { name: "topic", type: "uint8", indexed: false }, { name: "variant", type: "uint8", indexed: false },
      { name: "unknown", type: "bool", indexed: false }, { name: "neuralGenerated", type: "bool", indexed: false },
      { name: "prompt", type: "string", indexed: false }, { name: "response", type: "string", indexed: false },
      { name: "traceHash", type: "bytes32", indexed: false }, { name: "memoryRoot", type: "bytes32", indexed: false },
    ],
  },
] as const;

export const brainRegistryAbi = [
  { type: "function", name: "latestVersion", stateMutability: "view", inputs: [], outputs: [{ type: "uint32" }] },
  { type: "function", name: "recommendedVersion", stateMutability: "view", inputs: [], outputs: [{ type: "uint32" }] },
  {
    type: "function", name: "versionInfo", stateMutability: "view", inputs: [{ name: "version", type: "uint32" }],
    outputs: [{ name: "release", type: "tuple", components: [
      { name: "engine", type: "address" }, { name: "codeHash", type: "bytes32" },
      { name: "publishedAt", type: "uint64" }, { name: "enabledForUpgrade", type: "bool" },
      { name: "label", type: "string" },
    ] }],
  },
] as const;

export const componentsAbi = [
  { type: "function", name: "MAX_COMPONENT_SUPPLY", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "totalMinted", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "catalogSealed", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "paymentToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "account", type: "address" }, { name: "id", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "isApprovedForAll", stateMutability: "view", inputs: [{ name: "account", type: "address" }, { name: "operator", type: "address" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "setApprovalForAll", stateMutability: "nonpayable", inputs: [{ name: "operator", type: "address" }, { name: "approved", type: "bool" }], outputs: [] },
  {
    type: "function", name: "definition", stateMutability: "view", inputs: [{ name: "id", type: "uint256" }],
    outputs: [{ name: "item", type: "tuple", components: [
      { name: "effectKind", type: "uint8" }, { name: "slot", type: "uint8" },
      { name: "power", type: "uint16" }, { name: "cap", type: "uint64" },
      { name: "minted", type: "uint64" }, { name: "mintPrice", type: "uint128" },
      { name: "publicMintEnabled", type: "bool" }, { name: "exists", type: "bool" },
    ] }],
  },
  { type: "function", name: "publicMint", stateMutability: "payable", inputs: [{ name: "id", type: "uint256" }, { name: "amount", type: "uint64" }], outputs: [] },
] as const;

export const marketAbi = [
  { type: "function", name: "nextListingId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "MARKET_FEE_BPS", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "paymentToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "owed", stateMutability: "view", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }] },
  {
    type: "function", name: "listings", stateMutability: "view", inputs: [{ name: "listingId", type: "uint256" }],
    outputs: [
      { name: "seller", type: "address" }, { name: "asset", type: "address" },
      { name: "tokenId", type: "uint256" }, { name: "unitPrice", type: "uint128" },
      { name: "amount", type: "uint96" }, { name: "assetKind", type: "uint8" },
    ],
  },
  { type: "function", name: "listAI", stateMutability: "nonpayable", inputs: [{ name: "asset", type: "address" }, { name: "tokenId", type: "uint256" }, { name: "price", type: "uint128" }], outputs: [{ name: "listingId", type: "uint256" }] },
  { type: "function", name: "listComponents", stateMutability: "nonpayable", inputs: [{ name: "asset", type: "address" }, { name: "tokenId", type: "uint256" }, { name: "amount", type: "uint96" }, { name: "unitPrice", type: "uint128" }], outputs: [{ name: "listingId", type: "uint256" }] },
  { type: "function", name: "buy", stateMutability: "payable", inputs: [{ name: "listingId", type: "uint256" }, { name: "amount", type: "uint96" }], outputs: [] },
  { type: "function", name: "cancel", stateMutability: "nonpayable", inputs: [{ name: "listingId", type: "uint256" }], outputs: [] },
  { type: "function", name: "withdraw", stateMutability: "nonpayable", inputs: [], outputs: [] },
  {
    type: "event", name: "Listed", inputs: [
      { name: "listingId", type: "uint256", indexed: true }, { name: "seller", type: "address", indexed: true },
      { name: "asset", type: "address", indexed: true }, { name: "tokenId", type: "uint256", indexed: false },
      { name: "amount", type: "uint96", indexed: false }, { name: "unitPrice", type: "uint128", indexed: false },
      { name: "assetKind", type: "uint8", indexed: false },
    ],
  },
] as const;

export const intentNames = [
  "问候", "身份", "能力", "链上真实性", "市场价格", "安全风险", "合约解释", "代币经济", "DeFi", "NFT", "钱包", "交易", "Gas", "代码", "比较", "规划", "脑暴", "幽默", "积极情绪", "消极情绪", "感谢", "告别", "隐私", "记忆", "治理", "追问", "未知",
] as const;

export const holderVaultAbi = [
  { type: "function", name: "rewardToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "protocol", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "registeredAICount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalReceived", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalClaimed", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "claimable", stateMutability: "view", inputs: [{ name: "aiId", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "claimableMany", stateMutability: "view", inputs: [{ name: "aiIds", type: "uint256[]" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "sync", stateMutability: "nonpayable", inputs: [], outputs: [{ name: "received", type: "uint256" }, { name: "allocated", type: "uint256" }] },
  { type: "function", name: "claim", stateMutability: "nonpayable", inputs: [{ name: "aiIds", type: "uint256[]" }, { name: "recipient", type: "address" }], outputs: [{ name: "amount", type: "uint256" }] },
] as const;

export type DeploymentConfig = {
  engineVersion: number;
  chainId: number;
  chainName: string;
  nativeSymbol: string;
  explorerBaseUrl: string;
  walletRpcUrl?: string;
  chatAddress: `0x${string}` | null;
  protocolAddress?: `0x${string}` | null;
  componentsAddress?: `0x${string}` | null;
  marketAddress?: `0x${string}` | null;
  brainRegistryAddress?: `0x${string}` | null;
  protocolFromBlock?: number;
  settlementMode?: "native" | "token";
  paymentTokenAddress?: `0x${string}` | null;
  paymentTokenSymbol?: string;
  paymentTokenDecimals?: number;
  holderVaultAddress?: `0x${string}` | null;
  rewardAssetSymbol?: string;
  rewardAssetDecimals?: number;
  buildLabel: string;
};
