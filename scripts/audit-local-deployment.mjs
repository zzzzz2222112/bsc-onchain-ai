#!/usr/bin/env node

import { readFile } from "node:fs/promises";

const rpcUrl = process.env.RPC_URL || "http://127.0.0.1:8545";
const sender = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";

async function rpc(method, params = []) {
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const payload = await response.json();
  if (payload.error) throw new Error(`${method}: ${payload.error.message}`);
  return payload.result;
}

async function batch(calls) {
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(calls.map(([method, params], index) => ({ jsonrpc: "2.0", id: index, method, params }))),
  });
  const payload = await response.json();
  const byId = new Map(payload.map((item) => [item.id, item]));
  return calls.map((_, index) => {
    const item = byId.get(index);
    if (!item || item.error) throw new Error(item?.error?.message || `missing batch response ${index}`);
    return item.result;
  });
}

const chainId = await rpc("eth_chainId");
if (chainId !== "0x7a69") throw new Error(`refusing to audit non-local chain ${chainId}`);

const latest = Number.parseInt(await rpc("eth_blockNumber"), 16);
const blocks = await batch(Array.from({ length: latest + 1 }, (_, number) => ["eth_getBlockByNumber", [`0x${number.toString(16)}`, true]]));
const transactions = blocks
  .flatMap((block) => block?.transactions || [])
  .filter((transaction) => transaction.from.toLowerCase() === sender && transaction.to === null)
  .sort((left, right) => Number.parseInt(left.nonce, 16) - Number.parseInt(right.nonce, 16));

if (transactions.length !== 26) throw new Error(`expected 26 creation transactions, found ${transactions.length}`);
transactions.forEach((transaction, nonce) => {
  if (Number.parseInt(transaction.nonce, 16) !== nonce) throw new Error(`missing or duplicate creation nonce ${nonce}`);
});

const receipts = await batch(transactions.map((transaction) => ["eth_getTransactionReceipt", [transaction.hash]]));
const codes = await batch(receipts.map((receipt) => ["eth_getCode", [receipt.contractAddress, "latest"]]));
const proofs = await batch(receipts.map((receipt) => ["eth_getProof", [receipt.contractAddress, [], "latest"]]));
const expectedRuntimeBytes = [
  ...Array(21).fill(24_001),
  10_255,
  15_280,
  14_917,
  2_200,
  12_769,
];

let deploymentGasUsed = 0;
const contracts = receipts.map((receipt, nonce) => {
  const runtimeBytes = (codes[nonce].length - 2) / 2;
  const gasUsed = Number.parseInt(receipt.gasUsed, 16);
  if (receipt.status !== "0x1") throw new Error(`creation nonce ${nonce} reverted`);
  if (runtimeBytes !== expectedRuntimeBytes[nonce]) {
    throw new Error(`nonce ${nonce} runtime bytes ${runtimeBytes}, expected ${expectedRuntimeBytes[nonce]}`);
  }
  deploymentGasUsed += gasUsed;
  const role = nonce < 22
    ? `weightsBlob[${nonce}]`
    : ["zhLexiconBlob", "enLexiconBlob", "modelCard", "freeChatEngine"][nonce - 22];
  return {
    nonce,
    role,
    address: receipt.contractAddress,
    runtimeBytes,
    codeHash: proofs[nonce].codeHash,
    gasUsed,
    txHash: receipt.transactionHash,
  };
});

const report = { chainId: Number.parseInt(chainId, 16), latestBlock: latest, contracts, deploymentGasUsed };
if (process.argv.includes("--verify-manifest")) {
  const manifestUrl = new URL("../deployments/local-31337.json", import.meta.url);
  const manifest = JSON.parse(await readFile(manifestUrl, "utf8"));
  if (manifest.chainId !== report.chainId || manifest.deploymentGasUsed !== report.deploymentGasUsed) {
    throw new Error("local manifest summary does not match the live chain");
  }
  for (const [index, contract] of report.contracts.entries()) {
    if (JSON.stringify(manifest.contracts[index]) !== JSON.stringify(contract)) {
      throw new Error(`local manifest contract ${index} does not match the live chain`);
    }
  }
  console.error("local manifest matches all 26 live creation receipts and code hashes");
}
console.log(JSON.stringify(report, null, 2));
