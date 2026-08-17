import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index === -1 || !process.argv[index + 1]) throw new Error(`Missing ${name}`);
  return process.argv[index + 1];
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function parseEnv(path) {
  return Object.fromEntries(
    readFileSync(path, "utf8")
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith("#") && line.includes("="))
      .map((line) => {
        const index = line.indexOf("=");
        return [line.slice(0, index).trim(), line.slice(index + 1).trim()];
      }),
  );
}

function asBigInt(value) {
  return BigInt(value);
}

function hexToBigInt(value) {
  return BigInt(value || "0x0");
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

const runFilePath = resolve(argument("--run-file"));
const walletFilePath = resolve(argument("--wallet-file"));
const outputPath = resolve(argument("--output"));
const gasPriceWei = asBigInt(argument("--gas-price-wei"));
const balanceWei = asBigInt(argument("--balance-wei"));
const run = JSON.parse(readFileSync(runFilePath, "utf8"));
const wallet = parseEnv(walletFilePath);

if (run.transactions.length !== roles.length || run.receipts.length !== roles.length) {
  throw new Error("The Forge run must contain exactly 45 transactions and receipts");
}
if (!/^0x[0-9a-fA-F]{40}$/.test(wallet.TINYAI_DEPLOYER_ADDRESS || "")) {
  throw new Error("Invalid deployer address");
}
if (!/^0x[0-9a-fA-F]{40}$/.test(wallet.TINYAI_TREASURY_ADDRESS || "")) {
  throw new Error("Invalid treasury address");
}

const transactions = run.transactions.map((entry, index) => {
  const receipt = run.receipts[index];
  const gasUsed = hexToBigInt(receipt.gasUsed);
  const gasLimit130 = (gasUsed * 130n + 99n) / 100n;
  const expectedType = [33, 36, 38, 39, 40, 41, 42, 43, 44].includes(index) ? "CALL" : "CREATE";
  if (entry.transactionType !== expectedType) {
    throw new Error(`Unexpected transaction type at index ${index}`);
  }
  if (hexToBigInt(entry.transaction.value) !== 0n || hexToBigInt(entry.transaction.nonce) !== BigInt(index)) {
    throw new Error(`Unexpected value or nonce at index ${index}`);
  }
  if (receipt.status !== "0x1") throw new Error(`Failed local receipt at index ${index}`);

  return {
    index,
    nonce: index,
    role: roles[index],
    type: entry.transactionType,
    contractName: entry.contractName || null,
    predictedContractAddress: entry.contractAddress || null,
    to: entry.transaction.to || null,
    valueWei: "0",
    gasUsed: gasUsed.toString(),
    gasLimit130: gasLimit130.toString(),
    inputSha256: sha256(entry.transaction.input || "0x"),
  };
});

const totalGasUsed = transactions.reduce((sum, item) => sum + BigInt(item.gasUsed), 0n);
const totalGasLimit130 = transactions.reduce((sum, item) => sum + BigInt(item.gasLimit130), 0n);
const expectedCostWei = totalGasUsed * gasPriceWei;
const maximumPlannedCostWei = totalGasLimit130 * gasPriceWei;
const canonical = transactions.map(({ index, nonce, role, type, predictedContractAddress, to, valueWei, gasLimit130, inputSha256 }) =>
  [index, nonce, role, type, predictedContractAddress || "", to || "", valueWei, gasLimit130, inputSha256].join("|"),
);

const manifest = {
  status: "FULL_NEW_STACK_PREFLIGHT_ONLY_NOT_BROADCAST",
  generatedAt: new Date().toISOString(),
  chainId: 56,
  sourceScript: "contracts/script/DeployFullProtocol.s.sol:DeployFullProtocol",
  sourceRunFile: runFilePath,
  sender: wallet.TINYAI_DEPLOYER_ADDRESS,
  protocolOwner: wallet.TINYAI_DEPLOYER_ADDRESS,
  treasury: wallet.TINYAI_TREASURY_ADDRESS,
  componentBaseUri: "ipfs://tinyai/{id}.json",
  compiler: {
    solc: "0.8.30",
    optimizer: true,
    optimizerRuns: 20_000,
    viaIR: true,
    evmVersion: "cancun",
  },
  invariants: {
    reusesExistingContracts: false,
    transactionCount: 45,
    contractCreateCount: 36,
    callCount: 9,
    firstNonce: 0,
    lastNonce: 44,
    everyNativeValueWei: "0",
    aiSupplyCap: 10_000,
    componentLifetimeSupplyCap: 100_000,
    aiMintPriceWei: "100000000000000",
    componentMintPriceWei: "100000000000000",
    marketFeeBps: 0,
  },
  economics: {
    gasPriceWei: gasPriceWei.toString(),
    deployerBalanceWei: balanceWei.toString(),
    totalMeasuredGas: totalGasUsed.toString(),
    totalGasLimit130: totalGasLimit130.toString(),
    expectedCostWei: expectedCostWei.toString(),
    maximumPlannedCostWei: maximumPlannedCostWei.toString(),
    balanceCoversMaximum: balanceWei >= maximumPlannedCostWei,
  },
  planSha256: sha256(`${canonical.join("\n")}\n`),
  transactions,
};

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(JSON.stringify({
  output: outputPath,
  transactions: manifest.invariants.transactionCount,
  creates: manifest.invariants.contractCreateCount,
  totalMeasuredGas: manifest.economics.totalMeasuredGas,
  maximumPlannedCostWei: manifest.economics.maximumPlannedCostWei,
  balanceCoversMaximum: manifest.economics.balanceCoversMaximum,
  planSha256: manifest.planSha256,
}));
