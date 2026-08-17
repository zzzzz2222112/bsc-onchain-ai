#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const ZERO = "0x0000000000000000000000000000000000000000";
const roles = [
  ...Array.from({ length: 22 }, (_, index) => `weightsBlob[${index}]`),
  "zhLexiconBlob", "enLexiconBlob", "modelCard", "freeChatEngine",
];
const runtimeBytes = [...Array(21).fill(24_001), 10_255, 15_280, 14_917, 2_200, 12_769];

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  if (index === -1) return fallback;
  if (!process.argv[index + 1]) throw new Error(`${name} requires a value`);
  return process.argv[index + 1];
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function lower(value) {
  return typeof value === "string" ? value.toLowerCase() : value;
}

function addressWord(value) {
  assert(/^0x[0-9a-fA-F]{64}$/.test(value), `invalid address return word: ${value}`);
  return `0x${value.slice(-40)}`.toLowerCase();
}

function quantity(value) {
  assert(typeof value === "string" && /^0x[0-9a-fA-F]+$/.test(value), `invalid RPC quantity: ${value}`);
  return BigInt(value);
}

function encodeIndex(index) {
  return index.toString(16).padStart(64, "0");
}

const manifestPath = resolve(argument("--manifest", "deployments/local-31337.json"));
const runFilePath = argument("--run-file");
const rpcUrl = argument("--rpc-url", process.env.RPC_URL || "http://127.0.0.1:8545");
const requireTransactions = process.argv.includes("--require-transactions");
const outputPath = argument("--output");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const run = runFilePath ? JSON.parse(await readFile(resolve(runFilePath), "utf8")) : null;

assert(Array.isArray(manifest.contracts) && manifest.contracts.length === 26, "manifest must contain exactly 26 contracts");
const expected = manifest.contracts.map((item, index) => {
  assert(item.nonce === index && item.role === roles[index], `manifest order mismatch at index ${index}`);
  const address = item.address || item.predictedAddress;
  assert(/^0x[0-9a-fA-F]{40}$/.test(address), `invalid contract address at index ${index}`);
  return {
    nonce: index,
    role: roles[index],
    address,
    runtimeBytes: item.runtimeBytes ?? manifest.preflightSimulation?.runtimeBytes?.[index] ?? runtimeBytes[index],
    expectedCodeHash: item.codeHash || item.expectedCodeHash || manifest.preflightSimulation?.codeHashes?.[index] || null,
    txHash: item.txHash || run?.transactions?.[index]?.hash || null,
    expectedGasUsed: item.gasUsed ?? null,
  };
});

let requestId = 0;
async function rpc(method, params = []) {
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++requestId, method, params }),
  });
  assert(response.ok, `${method} returned HTTP ${response.status}`);
  const payload = await response.json();
  if (payload.error) throw new Error(`${method}: ${payload.error.message}`);
  return payload.result;
}

async function batch(calls) {
  const results = [];
  for (let offset = 0; offset < calls.length; offset += 10) {
    const chunk = calls.slice(offset, offset + 10);
    const requests = chunk.map(([method, params]) => ({ jsonrpc: "2.0", id: ++requestId, method, params }));
    const response = await fetch(rpcUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(requests),
    });
    assert(response.ok, `RPC batch returned HTTP ${response.status}`);
    const payload = await response.json();
    assert(Array.isArray(payload), "RPC batch response is not an array");
    const byId = new Map(payload.map((item) => [item.id, item]));
    for (const request of requests) {
      const item = byId.get(request.id);
      if (!item || item.error) throw new Error(item?.error?.message || `missing batch response ${request.id}`);
      results.push(item.result);
    }
  }
  return results;
}

async function call(address, data) {
  return rpc("eth_call", [{ to: address, data }, "latest"]);
}

const chainId = Number(quantity(await rpc("eth_chainId")));
assert(chainId === manifest.chainId, `chain ID ${chainId} does not match manifest ${manifest.chainId}`);
const latestBlock = Number(quantity(await rpc("eth_blockNumber")));

const codes = await batch(expected.map((item) => ["eth_getCode", [item.address, "latest"]]));
const proofs = await batch(expected.map((item) => ["eth_getProof", [item.address, [], "latest"]]));
const contracts = expected.map((item, index) => {
  const actualRuntimeBytes = (codes[index].length - 2) / 2;
  const codeHash = proofs[index].codeHash;
  assert(codes[index] !== "0x", `${item.role} has no live code at ${item.address}`);
  assert(actualRuntimeBytes === item.runtimeBytes, `${item.role} runtime is ${actualRuntimeBytes} bytes, expected ${item.runtimeBytes}`);
  if (item.expectedCodeHash) {
    assert(lower(codeHash) === lower(item.expectedCodeHash), `${item.role} code hash differs from the manifest`);
  }
  return { nonce: item.nonce, role: item.role, address: item.address, runtimeBytes: actualRuntimeBytes, codeHash };
});

const txHashes = expected.map((item) => item.txHash);
const presentTxHashes = txHashes.filter((value) => typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value));
if (requireTransactions) assert(presentTxHashes.length === 26, "all 26 transaction hashes are required for post-deployment audit");
let deploymentGasUsed = null;
let deployer = manifest.deployer || null;
if (presentTxHashes.length === 26) {
  const transactions = await batch(txHashes.map((hash) => ["eth_getTransactionByHash", [hash]]));
  const receipts = await batch(txHashes.map((hash) => ["eth_getTransactionReceipt", [hash]]));
  deployer ||= transactions[0]?.from;
  assert(/^0x[0-9a-fA-F]{40}$/.test(deployer), "deployment sender is missing");
  deploymentGasUsed = 0n;
  transactions.forEach((transaction, index) => {
    const receipt = receipts[index];
    assert(transaction && receipt, `missing transaction or receipt at index ${index}`);
    assert(lower(transaction.from) === lower(deployer), `sender mismatch at index ${index}`);
    assert(transaction.to === null, `transaction ${index} is not a CREATE`);
    assert(quantity(transaction.nonce) === BigInt(index), `nonce mismatch at index ${index}`);
    assert(quantity(transaction.value) === 0n, `transaction ${index} transferred native value`);
    assert(receipt.status === "0x1", `creation transaction ${index} reverted`);
    assert(lower(receipt.contractAddress) === lower(expected[index].address), `receipt address mismatch at index ${index}`);
    const gasUsed = quantity(receipt.gasUsed);
    if (expected[index].expectedGasUsed !== null) {
      assert(gasUsed === BigInt(expected[index].expectedGasUsed), `gas-used mismatch at index ${index}`);
    }
    deploymentGasUsed += gasUsed;
    contracts[index].txHash = transaction.hash;
    contracts[index].gasUsed = gasUsed.toString();
  });
}

const modelCard = expected[24].address;
const chat = expected[25].address;
const [integrity, corpus, modelSize, activeFeatures, chunkCount, modelVersion] = await Promise.all([
  call(modelCard, "0x6cbe98fc"),
  call(modelCard, "0x207c8e3c"),
  call(modelCard, "0xdc6dd0ae"),
  call(modelCard, "0xd80cce15"),
  call(modelCard, "0xc7c47169"),
  call(modelCard, "0xffa1ad74"),
]);
assert(quantity(integrity) === 1n, "model-card integrityOk() is false");
assert(lower(corpus) === `0x${lower(manifest.model.corpusSha256)}`, "corpus commitment mismatch");
assert(quantity(modelSize) === BigInt(manifest.model.modelBytes), "model byte count mismatch");
assert(quantity(activeFeatures) === BigInt(manifest.model.activeFeatures), "active feature count mismatch");
assert(quantity(chunkCount) === 22n && quantity(modelVersion) === 3n, "model-card version or chunk count mismatch");

const modelLinks = await batch([
  ...Array.from({ length: 22 }, (_, index) => ["eth_call", [{ to: modelCard, data: `0xcd51a0dc${encodeIndex(index)}` }, "latest"]]),
  ["eth_call", [{ to: modelCard, data: "0x01703540" }, "latest"]],
  ["eth_call", [{ to: modelCard, data: "0x926b21d2" }, "latest"]],
]);
modelLinks.forEach((word, index) => {
  assert(addressWord(word) === lower(expected[index].address), `${roles[index]} is miswired in the model card`);
});

const [chatModel, paymentToken, treasury, fee, burn, chatVersion] = await Promise.all([
  call(chat, "0x923519fb"),
  call(chat, "0x3013ce29"),
  call(chat, "0x61d027b3"),
  call(chat, "0x1608b507"),
  call(chat, "0x53deb3d6"),
  call(chat, "0xffa1ad74"),
]);
const economics = manifest.constructorEconomics || { paymentToken: ZERO, treasury: ZERO, feePerChat: "0", burnBps: 0 };
assert(addressWord(chatModel) === lower(modelCard), "chat points to the wrong model card");
assert(addressWord(paymentToken) === lower(economics.paymentToken), "chat payment token mismatch");
assert(addressWord(treasury) === lower(economics.treasury), "chat treasury mismatch");
assert(quantity(fee) === BigInt(economics.feePerChat), "chat fee mismatch");
assert(quantity(burn) === BigInt(economics.burnBps), "chat burn share mismatch");
assert(quantity(chatVersion) === 3n, "chat version mismatch");

const runtimePlanSha256 = createHash("sha256")
  .update(`${contracts.map((item) => [item.nonce, item.role, lower(item.address), item.runtimeBytes, lower(item.codeHash)].join("|")).join("\n")}\n`)
  .digest("hex");
if (manifest.preflightSimulation?.runtimePlanSha256) {
  assert(manifest.preflightSimulation.runtimePlanSha256 === runtimePlanSha256, "runtime plan hash differs from the manifest");
}

const report = {
  ok: true,
  status: "CORE_DEPLOYMENT_LIVE_VERIFIED",
  auditedAt: new Date().toISOString(),
  chainId,
  latestBlock,
  sourceManifest: manifestPath,
  deployer,
  contractCount: contracts.length,
  transactionsVerified: presentTxHashes.length === 26,
  deploymentGasUsed: deploymentGasUsed?.toString() ?? null,
  modelCard,
  freeChatEngine: chat,
  runtimePlanSha256,
  constructorEconomics: {
    paymentToken: addressWord(paymentToken),
    treasury: addressWord(treasury),
    feePerChat: quantity(fee).toString(),
    burnBps: Number(quantity(burn)),
  },
  contracts,
};
if (outputPath) {
  assert(presentTxHashes.length === 26, "refusing to write a final audit report without all 26 transaction proofs");
  await writeFile(resolve(outputPath), `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
}
console.log(JSON.stringify(report, null, 2));
