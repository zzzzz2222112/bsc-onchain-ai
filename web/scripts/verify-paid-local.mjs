import {
  createPublicClient,
  decodeFunctionData,
  defineChain,
  getAddress,
  http,
  keccak256,
  parseEther,
} from "viem";
import { readFile } from "node:fs/promises";

const rpcUrl = process.env.RPC_URL || "http://127.0.0.1:8545";
const manifest = JSON.parse(await readFile(new URL("../../deployments/local-paid-31337.json", import.meta.url), "utf8"));
const chain = defineChain({
  id: 31337,
  name: "Local Anvil",
  nativeCurrency: { name: "Test Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [rpcUrl] } },
});
const client = createPublicClient({ chain, transport: http(rpcUrl) });
const token = getAddress(manifest.token.address);
const chat = getAddress(manifest.paidChat.address);
const user = getAddress(manifest.testAccounts.paidDeployerAndUser);
const treasury = getAddress(manifest.testAccounts.treasury);
const liquidity = getAddress(manifest.testAccounts.liquidity);
const burnSink = getAddress("0x000000000000000000000000000000000000dEaD");

const tokenAbi = [
  { type: "function", name: "totalSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "nonces", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "value", type: "uint256" }], outputs: [{ type: "bool" }] },
];
const resultComponents = [
  { name: "response", type: "string" }, { name: "intent", type: "uint8" }, { name: "secondaryIntent", type: "uint8" },
  { name: "sentiment", type: "uint8" }, { name: "nextMood", type: "int8" }, { name: "confidence", type: "uint16" },
  { name: "variant", type: "uint8" }, { name: "nextContext", type: "bytes32" }, { name: "chinese", type: "bool" },
  { name: "followedContext", type: "bool" },
];
const chatAbi = [
  { type: "function", name: "modelCard", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "paymentToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "treasury", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "feePerChat", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "burnBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "totalChats", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "memoryOf", stateMutability: "view", inputs: [{ name: "user", type: "address" }], outputs: [{ name: "memory", type: "tuple", components: [
    { name: "turns", type: "uint32" }, { name: "lastIntent", type: "uint8" }, { name: "mood", type: "int8" },
    { name: "confidence", type: "uint16" }, { name: "rollingContext", type: "bytes32" },
  ] }] },
  { type: "function", name: "chat", stateMutability: "nonpayable", inputs: [{ name: "prompt", type: "string" }], outputs: [{ name: "result", type: "tuple", components: resultComponents }] },
  { type: "function", name: "chatWithPermit", stateMutability: "nonpayable", inputs: [
    { name: "prompt", type: "string" }, { name: "deadline", type: "uint256" }, { name: "v", type: "uint8" },
    { name: "r", type: "bytes32" }, { name: "s", type: "bytes32" },
  ], outputs: [{ name: "result", type: "tuple", components: resultComponents }] },
];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function receiptAndTransaction(hash) {
  return Promise.all([client.getTransactionReceipt({ hash }), client.getTransaction({ hash })]);
}

assert(await client.getChainId() === 31337, "refusing to verify a non-local chain");
const [[tokenReceipt, tokenTx], [chatReceipt, chatTx], [permitReceipt, permitTx], [approvalReceipt, approvalTx], [approvedChatReceipt, approvedChatTx]] = await Promise.all([
  receiptAndTransaction(manifest.token.deploymentTx),
  receiptAndTransaction(manifest.paidChat.deploymentTx),
  receiptAndTransaction(manifest.permitPath.chatTx),
  receiptAndTransaction(manifest.approvePath.approvalTx),
  receiptAndTransaction(manifest.approvePath.chatTx),
]);
for (const receipt of [tokenReceipt, chatReceipt, permitReceipt, approvalReceipt, approvedChatReceipt]) {
  assert(receipt.status === "success", `transaction reverted: ${receipt.transactionHash}`);
}
assert(tokenTx.from.toLowerCase() === user.toLowerCase() && tokenTx.to === null && tokenTx.nonce === 0, "token CREATE provenance mismatch");
assert(chatTx.from.toLowerCase() === user.toLowerCase() && chatTx.to === null && chatTx.nonce === 1, "paid chat CREATE provenance mismatch");
assert(getAddress(tokenReceipt.contractAddress) === token && getAddress(chatReceipt.contractAddress) === chat, "creation address mismatch");

const [tokenCode, chatCode, modelCard, configuredToken, configuredTreasury, configuredFee, configuredBurn, totalChats, memory, totalSupply, treasuryBalance, liquidityBalance, userBalance, burnBalance, allowance, permitNonce] = await Promise.all([
  client.getCode({ address: token }), client.getCode({ address: chat }),
  client.readContract({ address: chat, abi: chatAbi, functionName: "modelCard" }),
  client.readContract({ address: chat, abi: chatAbi, functionName: "paymentToken" }),
  client.readContract({ address: chat, abi: chatAbi, functionName: "treasury" }),
  client.readContract({ address: chat, abi: chatAbi, functionName: "feePerChat" }),
  client.readContract({ address: chat, abi: chatAbi, functionName: "burnBps" }),
  client.readContract({ address: chat, abi: chatAbi, functionName: "totalChats" }),
  client.readContract({ address: chat, abi: chatAbi, functionName: "memoryOf", args: [user] }),
  client.readContract({ address: token, abi: tokenAbi, functionName: "totalSupply" }),
  client.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [treasury] }),
  client.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [liquidity] }),
  client.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [user] }),
  client.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [burnSink] }),
  client.readContract({ address: token, abi: tokenAbi, functionName: "allowance", args: [user, chat] }),
  client.readContract({ address: token, abi: tokenAbi, functionName: "nonces", args: [user] }),
]);
assert(tokenCode && chatCode, "runtime code is missing");
assert((tokenCode.length - 2) / 2 === manifest.token.runtimeBytes && keccak256(tokenCode) === manifest.token.codeHash, "token runtime mismatch");
assert((chatCode.length - 2) / 2 === manifest.paidChat.runtimeBytes && keccak256(chatCode) === manifest.paidChat.codeHash, "paid chat runtime mismatch");
assert(getAddress(modelCard) === getAddress(manifest.reusedModel.modelCard), "model card reuse mismatch");
assert(getAddress(configuredToken) === token && getAddress(configuredTreasury) === treasury, "payment routing mismatch");
assert(configuredFee === BigInt(manifest.paidChat.feePerChat) && configuredBurn === manifest.paidChat.burnBps, "payment economics mismatch");
assert(totalSupply === BigInt(manifest.token.totalSupply), "fixed supply mismatch");
assert(totalChats === BigInt(manifest.finalState.totalChats) && memory.turns === manifest.finalState.memoryTurns, "persisted chat state mismatch");
assert(allowance === 0n && permitNonce === 1n, "final allowance or Permit nonce mismatch");
assert(treasuryBalance === parseEther("650000015") && liquidityBalance === parseEther("200000000"), "treasury or liquidity balance mismatch");
assert(userBalance === parseEther("149999980") && burnBalance === parseEther("5"), "user or burn balance mismatch");

assert(permitTx.from.toLowerCase() === user.toLowerCase() && getAddress(permitTx.to) === chat, "Permit chat transaction routing mismatch");
assert(approvalTx.from.toLowerCase() === user.toLowerCase() && getAddress(approvalTx.to) === token, "approval transaction routing mismatch");
assert(approvedChatTx.from.toLowerCase() === user.toLowerCase() && getAddress(approvedChatTx.to) === chat, "approved chat transaction routing mismatch");
const permitCall = decodeFunctionData({ abi: chatAbi, data: permitTx.input });
const approvalCall = decodeFunctionData({ abi: tokenAbi, data: approvalTx.input });
const approvedChatCall = decodeFunctionData({ abi: chatAbi, data: approvedChatTx.input });
assert(permitCall.functionName === "chatWithPermit", "Permit path did not use chatWithPermit");
assert(approvalCall.functionName === "approve" && approvalCall.args[0].toLowerCase() === chat.toLowerCase() && approvalCall.args[1] === parseEther("10"), "approval was not exact");
assert(approvedChatCall.functionName === "chat", "approve path did not use chat");
assert(tokenReceipt.gasUsed === BigInt(manifest.token.deploymentGas) && chatReceipt.gasUsed === BigInt(manifest.paidChat.deploymentGas), "deployment gas mismatch");
assert(permitReceipt.gasUsed === BigInt(manifest.permitPath.chatGas) && approvalReceipt.gasUsed === BigInt(manifest.approvePath.approvalGas) && approvedChatReceipt.gasUsed === BigInt(manifest.approvePath.chatGas), "payment-path gas mismatch");

console.log(JSON.stringify({
  ok: true,
  status: manifest.status,
  token,
  paidChat: chat,
  reusedModelCard: modelCard,
  totalChats: totalChats.toString(),
  memoryTurns: memory.turns,
  permitNonce: permitNonce.toString(),
  allowance: allowance.toString(),
}, null, 2));
