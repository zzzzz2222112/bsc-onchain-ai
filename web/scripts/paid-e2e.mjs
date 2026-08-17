import {
  createPublicClient,
  createWalletClient,
  decodeEventLog,
  defineChain,
  getAddress,
  http,
  keccak256,
  parseEther,
  parseSignature,
} from "viem";

const rpcUrl = process.env.RPC_URL || "http://127.0.0.1:8545";
const expectedChainId = 31337;
const paidDeployer = getAddress("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
const treasury = getAddress("0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC");
const liquidity = getAddress("0x90F79bf6EB2c4f870365E785982E1f101E93b906");
const community = paidDeployer;
const burnSink = getAddress("0x000000000000000000000000000000000000dEaD");
const fee = parseEther("10");
const expectedSupply = parseEther("1000000000");
const localGasPrice = 50_000_000n;
const localChain = defineChain({
  id: expectedChainId,
  name: "Local Anvil",
  nativeCurrency: { name: "Test Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [rpcUrl] } },
});

const publicClient = createPublicClient({ chain: localChain, transport: http(rpcUrl) });
const walletClient = createWalletClient({ account: paidDeployer, chain: localChain, transport: http(rpcUrl) });

const tokenAbi = [
  { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "totalSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "nonces", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "value", type: "uint256" }], outputs: [{ type: "bool" }] },
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
  { type: "function", name: "chat", stateMutability: "nonpayable", inputs: [{ name: "prompt", type: "string" }], outputs: [{ name: "result", type: "tuple", components: [
    { name: "response", type: "string" }, { name: "intent", type: "uint8" }, { name: "secondaryIntent", type: "uint8" },
    { name: "sentiment", type: "uint8" }, { name: "nextMood", type: "int8" }, { name: "confidence", type: "uint16" },
    { name: "variant", type: "uint8" }, { name: "nextContext", type: "bytes32" }, { name: "chinese", type: "bool" },
    { name: "followedContext", type: "bool" },
  ] }] },
  { type: "function", name: "chatWithPermit", stateMutability: "nonpayable", inputs: [
    { name: "prompt", type: "string" }, { name: "deadline", type: "uint256" }, { name: "v", type: "uint8" },
    { name: "r", type: "bytes32" }, { name: "s", type: "bytes32" },
  ], outputs: [{ name: "result", type: "tuple", components: [
    { name: "response", type: "string" }, { name: "intent", type: "uint8" }, { name: "secondaryIntent", type: "uint8" },
    { name: "sentiment", type: "uint8" }, { name: "nextMood", type: "int8" }, { name: "confidence", type: "uint16" },
    { name: "variant", type: "uint8" }, { name: "nextContext", type: "bytes32" }, { name: "chinese", type: "bool" },
    { name: "followedContext", type: "bool" },
  ] }] },
  { type: "event", name: "Chat", inputs: [
    { name: "user", type: "address", indexed: true }, { name: "turn", type: "uint32", indexed: true },
    { name: "intent", type: "uint8", indexed: true }, { name: "secondaryIntent", type: "uint8", indexed: false },
    { name: "sentiment", type: "uint8", indexed: false }, { name: "mood", type: "int8", indexed: false },
    { name: "confidence", type: "uint16", indexed: false }, { name: "variant", type: "uint8", indexed: false },
    { name: "feePaid", type: "uint256", indexed: false }, { name: "prompt", type: "string", indexed: false },
    { name: "response", type: "string", indexed: false }, { name: "contextHash", type: "bytes32", indexed: false },
    { name: "followedContext", type: "bool", indexed: false },
  ] },
];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function toJson(value) {
  return JSON.stringify(value, (_, item) => typeof item === "bigint" ? item.toString() : item, 2);
}

async function findCreationReceipts() {
  const latest = await publicClient.getBlockNumber();
  const transactions = [];
  for (let number = 0n; number <= latest; number += 1n) {
    const block = await publicClient.getBlock({ blockNumber: number, includeTransactions: true });
    for (const transaction of block.transactions) {
      if (typeof transaction !== "string" && transaction.from.toLowerCase() === paidDeployer.toLowerCase() && transaction.to === null) {
        transactions.push(transaction);
      }
    }
  }
  transactions.sort((left, right) => Number(left.nonce - right.nonce));
  assert(transactions.length === 2, `expected two paid deployment CREATEs, found ${transactions.length}`);
  assert(transactions[0].nonce === 0 && transactions[1].nonce === 1, "paid deployment nonces must be 0 and 1");
  return Promise.all(transactions.map((transaction) => publicClient.getTransactionReceipt({ hash: transaction.hash })));
}

function decodeChat(receipt) {
  for (const log of receipt.logs) {
    try {
      const decoded = decodeEventLog({ abi: chatAbi, data: log.data, topics: log.topics });
      if (decoded.eventName === "Chat") return decoded.args;
    } catch { /* token logs are expected */ }
  }
  throw new Error("missing Chat event");
}

const chainId = await publicClient.getChainId();
assert(chainId === expectedChainId, `refusing non-local chain ${chainId}`);
const localManifest = JSON.parse(await (await import("node:fs/promises")).readFile(new URL("../../deployments/local-31337.json", import.meta.url), "utf8"));
const expectedModelCard = getAddress(localManifest.contracts.find((item) => item.role === "modelCard").address);
const [tokenReceipt, chatReceipt] = await findCreationReceipts();
assert(tokenReceipt.status === "success" && chatReceipt.status === "success", "paid deployment reverted");
const token = getAddress(tokenReceipt.contractAddress);
const chat = getAddress(chatReceipt.contractAddress);
const [tokenCode, chatCode] = await Promise.all([publicClient.getCode({ address: token }), publicClient.getCode({ address: chat })]);
assert(tokenCode && chatCode, "paid deployment runtime code is missing");

const [name, symbol, totalSupply, modelCard, configuredToken, configuredTreasury, configuredFee, burnBps] = await Promise.all([
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "name" }),
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "symbol" }),
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "totalSupply" }),
  publicClient.readContract({ address: chat, abi: chatAbi, functionName: "modelCard" }),
  publicClient.readContract({ address: chat, abi: chatAbi, functionName: "paymentToken" }),
  publicClient.readContract({ address: chat, abi: chatAbi, functionName: "treasury" }),
  publicClient.readContract({ address: chat, abi: chatAbi, functionName: "feePerChat" }),
  publicClient.readContract({ address: chat, abi: chatAbi, functionName: "burnBps" }),
]);
assert(name === "TinyAI Test Token" && symbol === "TAIT", "unexpected token identity");
assert(totalSupply === expectedSupply, "unexpected fixed supply");
assert(getAddress(modelCard) === expectedModelCard, "paid chat did not reuse the verified model card");
assert(getAddress(configuredToken) === token && getAddress(configuredTreasury) === treasury, "paid chat routing mismatch");
assert(configuredFee === fee && burnBps === 2_500, "paid chat economics mismatch");

const [treasuryInitial, liquidityInitial, communityInitial, burnInitial, permitNonceInitial, userTxCountInitial] = await Promise.all([
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [treasury] }),
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [liquidity] }),
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [community] }),
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [burnSink] }),
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "nonces", args: [paidDeployer] }),
  publicClient.getTransactionCount({ address: paidDeployer }),
]);
assert(treasuryInitial === expectedSupply * 65n / 100n, "treasury allocation mismatch");
assert(liquidityInitial === expectedSupply * 20n / 100n, "liquidity allocation mismatch");
assert(communityInitial === expectedSupply * 15n / 100n, "community allocation mismatch");
assert(burnInitial === 0n && permitNonceInitial === 0n && userTxCountInitial === 2, "unexpected initial paid-test state");

const permitPrompt = "怎么保护我的钱包？";
const deadline = 1_900_000_000n; // Fixed local-only deadline keeps the test transaction reproducible.
assert((await publicClient.getBlock()).timestamp < deadline, "fixed local Permit deadline has expired");
const signature = await walletClient.signTypedData({
  account: paidDeployer,
  domain: { name, version: "1", chainId, verifyingContract: token },
  types: { Permit: [
    { name: "owner", type: "address" }, { name: "spender", type: "address" },
    { name: "value", type: "uint256" }, { name: "nonce", type: "uint256" }, { name: "deadline", type: "uint256" },
  ] },
  primaryType: "Permit",
  message: { owner: paidDeployer, spender: chat, value: fee, nonce: permitNonceInitial, deadline },
});
const parsed = parseSignature(signature);
const v = Number(parsed.v ?? BigInt((parsed.yParity ?? 0) + 27));
const permitSimulation = await publicClient.simulateContract({
  account: paidDeployer,
  address: chat,
  abi: chatAbi,
  functionName: "chatWithPermit",
  args: [permitPrompt, deadline, v, parsed.r, parsed.s],
});
const permitHash = await walletClient.writeContract({ ...permitSimulation.request, gasPrice: localGasPrice });
const permitReceipt = await publicClient.waitForTransactionReceipt({ hash: permitHash });
assert(permitReceipt.status === "success", "Permit chat reverted");
const permitEvent = decodeChat(permitReceipt);
assert(permitEvent.user.toLowerCase() === paidDeployer.toLowerCase() && permitEvent.feePaid === fee, "Permit Chat event mismatch");

const approvalSimulation = await publicClient.simulateContract({
  account: paidDeployer,
  address: token,
  abi: tokenAbi,
  functionName: "approve",
  args: [chat, fee],
});
const approvalHash = await walletClient.writeContract({ ...approvalSimulation.request, gasPrice: localGasPrice });
const approvalReceipt = await publicClient.waitForTransactionReceipt({ hash: approvalHash });
assert(approvalReceipt.status === "success", "fixed approval reverted");
assert(await publicClient.readContract({ address: token, abi: tokenAbi, functionName: "allowance", args: [paidDeployer, chat] }) === fee, "approval amount is not exact");

const approvePrompt = "继续说";
const chatSimulation = await publicClient.simulateContract({ account: paidDeployer, address: chat, abi: chatAbi, functionName: "chat", args: [approvePrompt] });
const approveChatHash = await walletClient.writeContract({ ...chatSimulation.request, gasPrice: localGasPrice });
const approveChatReceipt = await publicClient.waitForTransactionReceipt({ hash: approveChatHash });
assert(approveChatReceipt.status === "success", "approved chat reverted");
const approveEvent = decodeChat(approveChatReceipt);
assert(approveEvent.followedContext === true && approveEvent.feePaid === fee, "approved follow-up event mismatch");

const [treasuryFinal, liquidityFinal, communityFinal, burnFinal, allowanceFinal, permitNonceFinal, totalChats, memory, userTxCountFinal] = await Promise.all([
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [treasury] }),
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [liquidity] }),
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [community] }),
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "balanceOf", args: [burnSink] }),
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "allowance", args: [paidDeployer, chat] }),
  publicClient.readContract({ address: token, abi: tokenAbi, functionName: "nonces", args: [paidDeployer] }),
  publicClient.readContract({ address: chat, abi: chatAbi, functionName: "totalChats" }),
  publicClient.readContract({ address: chat, abi: chatAbi, functionName: "memoryOf", args: [paidDeployer] }),
  publicClient.getTransactionCount({ address: paidDeployer }),
]);
assert(treasuryFinal - treasuryInitial === parseEther("15"), "treasury did not receive 75% of two fees");
assert(liquidityFinal === liquidityInitial, "liquidity allocation changed during chat");
assert(communityInitial - communityFinal === parseEther("20"), "user did not pay exactly two fees");
assert(burnFinal - burnInitial === parseEther("5"), "burn sink did not receive 25% of two fees");
assert(allowanceFinal === 0n && permitNonceFinal === 1n, "allowance or Permit nonce mismatch");
assert(totalChats === 2n && memory.turns === 2, "paid chat memory was not persisted twice");
assert(userTxCountFinal - userTxCountInitial === 3, "Permit path should use one tx and approve path two txs");

const deploymentGas = tokenReceipt.gasUsed + chatReceipt.gasUsed;
const report = {
  status: "LOCAL_PAID_E2E_VERIFIED",
  chainId,
  reusedModelCard: expectedModelCard,
  token: {
    address: token,
    name,
    symbol,
    totalSupply,
    runtimeBytes: (tokenCode.length - 2) / 2,
    codeHash: keccak256(tokenCode),
    deploymentTx: tokenReceipt.transactionHash,
    deploymentGas: tokenReceipt.gasUsed,
    allocation: { treasury: treasuryInitial, liquidity: liquidityInitial, community: communityInitial },
  },
  paidChat: {
    address: chat,
    runtimeBytes: (chatCode.length - 2) / 2,
    codeHash: keccak256(chatCode),
    deploymentTx: chatReceipt.transactionHash,
    deploymentGas: chatReceipt.gasUsed,
    feePerChat: configuredFee,
    burnBps,
    treasury,
  },
  deploymentGas,
  permitPath: {
    signatureOnlyApproval: true,
    transactionCount: 1,
    chatTx: permitHash,
    chatGas: permitReceipt.gasUsed,
    intent: permitEvent.intent,
  },
  approvePath: {
    exactApproval: fee,
    transactionCount: 2,
    approvalTx: approvalHash,
    approvalGas: approvalReceipt.gasUsed,
    chatTx: approveChatHash,
    chatGas: approveChatReceipt.gasUsed,
    followedContext: approveEvent.followedContext,
  },
  finalState: {
    totalChats,
    memoryTurns: memory.turns,
    permitNonce: permitNonceFinal,
    allowance: allowanceFinal,
    treasuryFeesReceived: treasuryFinal - treasuryInitial,
    burned: burnFinal - burnInitial,
    userFeesPaid: communityInitial - communityFinal,
  },
};

console.log(toJson(report));
