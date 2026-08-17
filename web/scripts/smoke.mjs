import { createPublicClient, http } from "viem";

const baseUrl = process.env.APP_URL || "http://127.0.0.1:3000";
const chatAddress = process.env.CHAT_ADDRESS || process.env.NEXT_PUBLIC_CHAT_ADDRESS;
const expectedChainId = Number(process.env.EXPECTED_CHAIN_ID || process.env.NEXT_PUBLIC_CHAIN_ID || 31337);
const rpcUrl = `${baseUrl}/api/rpc`;
const versionAbi = [
  { type: "function", name: "VERSION", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
];
const v3ChatAbi = [
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
];
const v4ReasonerAbi = [
  {
    type: "function", name: "preview", stateMutability: "view",
    inputs: [
      { name: "user", type: "address" }, { name: "prompt", type: "string" }, { name: "depth", type: "uint8" },
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
];
const v5RetrieverAbi = [
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
];
const v6GeneratorAbi = [
  {
    type: "function", name: "preview", stateMutability: "view",
    inputs: [{ name: "user", type: "address" }, { name: "prompt", type: "string" }],
    outputs: [{ name: "result", type: "tuple", components: [
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
    ] }],
  },
];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

assert(/^0x[0-9a-fA-F]{40}$/.test(chatAddress || ""), "CHAT_ADDRESS or NEXT_PUBLIC_CHAT_ADDRESS is required");

const chainResponse = await fetch(rpcUrl, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_chainId", params: [] }),
});
const chain = await chainResponse.json();
assert(chain.result === `0x${expectedChainId.toString(16)}`, `unexpected chain: ${JSON.stringify(chain)}`);

const blockedResponse = await fetch(rpcUrl, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ jsonrpc: "2.0", id: 2, method: "eth_sendRawTransaction", params: ["0x00"] }),
});
const blocked = await blockedResponse.json();
assert(blockedResponse.status === 400 && blocked.error?.message === "RPC method is not allowed", "unsafe RPC method was not blocked");

const foreignResponse = await fetch(rpcUrl, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ jsonrpc: "2.0", id: 3, method: "eth_call", params: [{ to: "0x0000000000000000000000000000000000000001", data: "0x" }, "latest"] }),
});
const foreign = await foreignResponse.json();
assert(foreignResponse.status === 400 && foreign.error?.message === "Contract call target is not allowed", "foreign eth_call target was not blocked");

const client = createPublicClient({ transport: http(rpcUrl) });
const code = await client.getCode({ address: chatAddress });
assert(code && code !== "0x", `configured chat address has no runtime code: ${chatAddress}`);
const version = await client.readContract({ address: chatAddress, abi: versionAbi, functionName: "VERSION" });
let proof;
if (version === 3) {
  const result = await client.readContract({
    address: chatAddress,
    abi: v3ChatAbi,
    functionName: "preview",
    // This prompt is a frozen Python/Solidity parity vector, so an exact intent
    // assertion detects model-byte or inference drift instead of language quality.
    args: ["0x000000000000000000000000000000000000bEEF", "这次聊天真的在链上推理吗"],
  });
  assert(result.intent === 3, `unexpected intent: ${result.intent}`);
  assert(result.chinese === true && result.response.length > 20, "invalid v3 preview response");
  proof = { intent: result.intent, confidence: result.confidence, response: result.response };
} else if (version === 4) {
  const [result, universal] = await Promise.all([
    client.readContract({
      address: chatAddress,
      abi: v4ReasonerAbi,
      functionName: "preview",
      args: ["0x000000000000000000000000000000000000bEEF", "如果把 Gas 提高十倍，AI 会聪明十倍吗？", 1],
    }),
    client.readContract({
      address: chatAddress,
      abi: v4ReasonerAbi,
      functionName: "preview",
      args: ["0x000000000000000000000000000000000000bEEF", "恐龙为什么灭绝？", 1],
    }),
  ]);
  const gasNotIntelligence = 1n << 4n;
  const architectureMatters = 1n << 5n;
  const speculativeAnswer = 1n << 13n;
  assert((result.conclusions & gasNotIntelligence) !== 0n, "v4 missed the Gas/intelligence conclusion");
  assert((result.conclusions & architectureMatters) !== 0n, "v4 deep mode missed the architecture conclusion");
  assert(result.stepCount > 6 && result.traceHash !== `0x${"0".repeat(64)}`, "invalid v4 reasoning trace");
  assert(universal.domain === 0, `unseen topic was not routed to the universal path: ${universal.domain}`);
  assert((universal.conclusions & speculativeAnswer) !== 0n, "unseen topic missed the speculative-answer conclusion");
  assert(universal.response.includes("恐龙为什么灭绝？") && universal.response.includes("低置信度推测"), "universal answer is not prompt-conditioned or labeled");
  proof = {
    domain: result.domain,
    confidence: result.confidence,
    steps: result.stepCount,
    conclusions: result.conclusions.toString(),
    traceHash: result.traceHash,
    response: result.response,
    universalResponse: universal.response,
  };
} else if (version === 5) {
  const [known, unknown] = await Promise.all([
    client.readContract({
      address: chatAddress,
      abi: v5RetrieverAbi,
      functionName: "preview",
      args: ["0x000000000000000000000000000000000000bEEF", "你知道什么是 BSC 吗？"],
    }),
    client.readContract({
      address: chatAddress,
      abi: v5RetrieverAbi,
      functionName: "preview",
      args: ["0x000000000000000000000000000000000000bEEF", "怎么做红烧肉？"],
    }),
  ]);
  assert(known.topic === 3 && known.factCount === 3 && known.unknown === false, "v5 did not retrieve the three BSC facts");
  assert(known.factIds[0] === 1301 && known.evidence.includes("[1301]") && known.response.includes("结论"), "v5 BSC evidence is incomplete");
  assert(known.traceHash !== `0x${"0".repeat(64)}` && known.trace.length === 5, "v5 retrieval trace is invalid");
  assert(unknown.topic === 0 && unknown.factCount === 0 && unknown.unknown === true, "v5 did not stop at the unknown boundary");
  assert(unknown.response.includes("为了不误导你") && unknown.evidence.includes("没有检索到"), "v5 unknown answer is not polite or evidenced");
  assert(!unknown.response.includes("低置信度推测"), "v5 revived the rejected universal-answer fallback");
  proof = {
    topic: known.topic,
    classifierIntent: known.intent,
    classifierConfidence: known.classifierConfidence,
    matchScore: known.matchScore,
    factIds: known.factIds,
    traceHash: known.traceHash,
    response: known.response,
    evidence: known.evidence,
    unknownResponse: unknown.response,
  };
} else if (version === 6) {
  const [known, unknown] = await Promise.all([
    client.readContract({
      address: chatAddress,
      abi: v6GeneratorAbi,
      functionName: "preview",
      args: ["0x000000000000000000000000000000000000bEEF", "你知道什么是 BSC 吗？"],
    }),
    client.readContract({
      address: chatAddress,
      abi: v6GeneratorAbi,
      functionName: "preview",
      args: ["0x000000000000000000000000000000000000bEEF", "恐龙为什么灭绝？"],
    }),
  ]);
  assert(known.topic === 3 && known.neuralContext === 1 && known.neuralGenerated === true, "v6 did not route BSC to the neural generator");
  assert(known.factIds[0] === 1301 && known.factCount === 3, "v6 neural answer lost v5 factual grounding");
  assert(known.tokenCount > 0 && known.stepCount === known.tokenCount + 1, "v6 token trace is incomplete");
  assert(known.generationTraceHash !== `0x${"0".repeat(64)}` && known.response.includes("BSC"), "v6 generated response is invalid");
  assert(unknown.neuralGenerated === false && unknown.neuralContext === 255, "v6 unknown topic did not use the safe fallback");
  assert(unknown.unknown === true && unknown.tokenCount === 0 && unknown.response.includes("为了不误导你"), "v6 unknown fallback is invalid");
  proof = {
    topic: known.topic,
    neuralContext: known.neuralContext,
    variant: known.variant,
    tokenCount: known.tokenCount,
    tokenIds: known.tokenIds.slice(0, known.tokenCount),
    tokenScores: known.tokenScores.slice(0, known.stepCount),
    factIds: known.factIds,
    retrievalTraceHash: known.retrievalTraceHash,
    generationTraceHash: known.generationTraceHash,
    response: known.response,
    unknownResponse: unknown.response,
  };
} else {
  throw new Error(`unsupported engine version: ${version}`);
}

console.log(JSON.stringify({
  ok: true,
  chainId: chain.result,
  version,
  ...proof,
  blockedMethod: blocked.error.message,
  blockedForeignTarget: foreign.error.message,
}, null, 2));
