import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index === -1 || !process.argv[index + 1]) throw new Error(`Missing ${name}`);
  return process.argv[index + 1];
}

function sha256Hex(value) {
  if (!/^0x[0-9a-fA-F]*$/.test(value)) throw new Error("Expected hexadecimal input");
  return createHash("sha256").update(Buffer.from(value.slice(2), "hex")).digest("hex");
}

function quantity(value) {
  return BigInt(value ?? "0x0");
}

function lower(value) {
  return typeof value === "string" ? value.toLowerCase() : value;
}

const roles = [
  ...Array.from({ length: 22 }, (_, index) => `weightsBlob[${index}]`),
  "zhLexiconBlob",
  "enLexiconBlob",
  "modelCard",
  "classifierV3",
  "knowledgeV5",
  "retrieverV5",
  "generatorV6ModelBlob",
  "generatorV6LexiconBlob",
  "generatorV6",
  "genesisBrainV1",
  "brainRegistry",
  "publishGenesisBrain",
  "components",
  "AIProtocol",
  "bindComponents",
  "market",
  "defineMemoryCell",
  "defineCuriosityGene",
  "defineEmpathyGene",
  "defineHumorGene",
  "defineCautionGene",
  "defineExpressionCore",
  "sealComponentCatalog",
];

const createIndexes = new Set(roles.map((_, index) => index).filter((index) => ![33, 36, 38, 39, 40, 41, 42, 43, 44].includes(index)));
const runFilePath = resolve(argument("--run-file"));
const runtimeAuditPath = resolve(argument("--runtime-audit"));
const outputPath = resolve(argument("--output"));
const run = JSON.parse(readFileSync(runFilePath, "utf8"));
const runtimeAudit = JSON.parse(readFileSync(runtimeAuditPath, "utf8"));

if (run.chain !== 56 || runtimeAudit.chainId !== 56) throw new Error("Expected BNB Smart Chain mainnet (chain 56)");
if (run.transactions?.length !== roles.length || run.receipts?.length !== roles.length) {
  throw new Error("The Foundry broadcast artifact must contain exactly 45 transactions and 45 receipts");
}
if (runtimeAudit.records?.length !== 36) throw new Error("The runtime audit must contain exactly 36 CREATE addresses");
for (const record of runtimeAudit.records) {
  if (!/^0x[0-9a-fA-F]{40}$/.test(record.address)) throw new Error(`Invalid runtime-audit address: ${record.address}`);
  if (!Number.isInteger(record.runtimeBytes) || record.runtimeBytes <= 0) throw new Error(`Invalid runtime size for ${record.address}`);
  if (!/^0x[0-9a-fA-F]{64}$/.test(record.runtimeCodeHash)) throw new Error(`Invalid runtime hash for ${record.address}`);
}

const runtimeByAddress = new Map(runtimeAudit.records.map((record) => [lower(record.address), record]));
if (runtimeByAddress.size !== runtimeAudit.records.length) throw new Error("The runtime audit contains duplicate addresses");
const firstNonce = Number(quantity(run.transactions[0].transaction.nonce));
if (firstNonce !== 60) throw new Error(`Expected the formal deployment to start at nonce 60, received ${firstNonce}`);
const sender = lower(run.transactions[0].transaction.from);
const transactions = run.transactions.map((entry, index) => {
  const receipt = run.receipts[index];
  const expectedType = createIndexes.has(index) ? "CREATE" : "CALL";
  const nonce = Number(quantity(entry.transaction.nonce));
  const gasUsed = quantity(receipt.gasUsed);
  const effectiveGasPriceWei = quantity(receipt.effectiveGasPrice);
  const address = entry.contractAddress ? lower(entry.contractAddress) : null;
  const runtime = address ? runtimeByAddress.get(address) : null;

  if (entry.transactionType !== expectedType) throw new Error(`Unexpected transaction type at index ${index}`);
  if (nonce !== firstNonce + index) throw new Error(`Non-contiguous nonce at index ${index}`);
  if (lower(entry.transaction.from) !== sender) throw new Error(`Sender drift at index ${index}`);
  if (quantity(entry.transaction.value) !== 0n) throw new Error(`Non-zero native value at index ${index}`);
  if (receipt.status !== "0x1") throw new Error(`Failed receipt at index ${index}`);
  if (lower(receipt.transactionHash) !== lower(entry.hash)) throw new Error(`Receipt/hash mismatch at index ${index}`);
  if (expectedType === "CREATE" && !runtime) throw new Error(`Missing runtime audit for ${address}`);

  return {
    index,
    nonce,
    role: roles[index],
    type: expectedType,
    contractName: entry.contractName || null,
    address,
    to: entry.transaction.to ? lower(entry.transaction.to) : null,
    function: entry.function || null,
    transactionHash: lower(entry.hash),
    blockNumber: Number(quantity(receipt.blockNumber)),
    gasUsed: gasUsed.toString(),
    effectiveGasPriceWei: effectiveGasPriceWei.toString(),
    gasCostWei: (gasUsed * effectiveGasPriceWei).toString(),
    valueWei: "0",
    inputSha256: sha256Hex(entry.transaction.input || "0x"),
    status: 1,
    ...(runtime ? {
      runtimeBytes: runtime.runtimeBytes,
      runtimeCodeHash: lower(runtime.runtimeCodeHash),
    } : {}),
  };
});

const totalGasUsed = transactions.reduce((sum, item) => sum + BigInt(item.gasUsed), 0n);
const actualGasCostWei = transactions.reduce((sum, item) => sum + BigInt(item.gasCostWei), 0n);
const blocks = transactions.map((item) => item.blockNumber);
const canonicalEvidence = transactions.map((item) => [
  item.index,
  item.nonce,
  item.role,
  item.type,
  item.address || "",
  item.to || "",
  item.transactionHash,
  item.blockNumber,
  item.gasUsed,
  item.effectiveGasPriceWei,
  item.inputSha256,
  item.runtimeCodeHash || "",
].join("|"));

const manifest = {
  schemaVersion: 1,
  status: "DEPLOYED_RECEIPTS_AND_RUNTIME_VERIFIED",
  chainId: 56,
  network: "BNB Smart Chain Mainnet",
  deploymentScript: "contracts/script/DeployFullProtocol.s.sol:DeployFullProtocol",
  foundryBroadcastArtifact: basename(runFilePath),
  artifactTimestamp: new Date(Number(run.timestamp)).toISOString(),
  deployer: sender,
  compiler: {
    solc: "0.8.30",
    optimizer: true,
    optimizerRuns: 20_000,
    viaIR: true,
    evmVersion: "cancun",
  },
  invariants: {
    transactionCount: 45,
    contractCreateCount: 36,
    callCount: 9,
    firstNonce,
    lastNonce: firstNonce + roles.length - 1,
    everyNativeValueWei: "0",
    firstBlock: Math.min(...blocks),
    lastBlock: Math.max(...blocks),
    aiSupplyCap: 10_000,
    componentLifetimeSupplyCap: 100_000,
    aiMintPriceWei: "100000000000000",
    componentMintPriceWei: "100000000000000",
    marketFeeBps: 0,
  },
  economics: {
    totalGasUsed: totalGasUsed.toString(),
    actualGasCostWei: actualGasCostWei.toString(),
  },
  runtimeAudit: {
    method: runtimeAudit.method,
    requestedBlockTag: runtimeAudit.requestedBlockTag,
    observedNoLaterThanBlock: runtimeAudit.observedNoLaterThanBlock,
    createAddressesChecked: runtimeAudit.records.length,
  },
  canonicalEvidenceSha256: createHash("sha256").update(`${canonicalEvidence.join("\n")}\n`).digest("hex"),
  transactions,
};

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(JSON.stringify({
  output: outputPath,
  transactions: manifest.invariants.transactionCount,
  creates: manifest.invariants.contractCreateCount,
  firstNonce: manifest.invariants.firstNonce,
  lastNonce: manifest.invariants.lastNonce,
  totalGasUsed: manifest.economics.totalGasUsed,
  actualGasCostWei: manifest.economics.actualGasCostWei,
  canonicalEvidenceSha256: manifest.canonicalEvidenceSha256,
}));
