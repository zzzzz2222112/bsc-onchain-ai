import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const draft = JSON.parse(readFileSync(resolve(root, "deployments/bsc-mainnet-core-draft.json"), "utf8"));
const local = JSON.parse(readFileSync(resolve(root, "deployments/local-31337.json"), "utf8"));
const model = JSON.parse(readFileSync(resolve(root, "model/build/manifest.json"), "utf8"));
const run = JSON.parse(readFileSync(resolve(root, "contracts/broadcast/Deploy.s.sol/56/dry-run/run-latest.json"), "utf8"));

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function quantity(value) {
  if (typeof value === "number") return BigInt(value);
  assert(typeof value === "string" && /^(0x[0-9a-fA-F]+|[0-9]+)$/.test(value), `invalid quantity: ${value}`);
  return BigInt(value);
}

function lower(value) {
  return typeof value === "string" ? value.toLowerCase() : value;
}

function close(actual, expected, tolerance = 1e-12) {
  return Math.abs(Number(actual) - Number(expected)) <= tolerance;
}

assert(draft.status === "DRAFT_ONLY_REQUIRES_FRESH_CONFIRMATION", "draft must remain confirmation-gated");
assert(draft.chainId === 56 && draft.preflightSimulation.chainId === 56, "draft must target BSC chain 56");
assert(draft.deployerNonce === 0 && draft.preflightSimulation.senderNonce === 0, "draft sender nonce must remain zero");
assert(draft.nativeValuePerTransactionWei === "0", "draft must declare zero native value");
assert(draft.constructorEconomics.paymentToken === "0x0000000000000000000000000000000000000000", "fee-free core must use the zero payment token");
assert(draft.constructorEconomics.treasury === "0x0000000000000000000000000000000000000000", "fee-free core must use the zero treasury");
assert(draft.constructorEconomics.feePerChat === "0" && draft.constructorEconomics.burnBps === 0, "fee-free economics drifted");
assert(Array.isArray(draft.contracts) && draft.contracts.length === 26, "draft must contain 26 contracts");
assert(Array.isArray(run.transactions) && run.transactions.length === 26, "chain-56 dry run must contain 26 transactions");

assert(draft.model.modelSha256 === model.modelSha256, "model SHA-256 drifted from the generated manifest");
assert(draft.model.corpusSha256 === model.corpusSha256, "corpus SHA-256 drifted from the generated manifest");
assert(draft.model.modelBytes === model.modelBytes, "model byte count drifted");
assert(draft.model.activeFeatures === model.activeFeatures, "active feature count drifted");
assert(draft.model.intents === model.intentCount && draft.model.modelChunks === model.chunks.length, "model shape drifted");
assert(Array.isArray(draft.preflightSimulation.runtimeBytes) && draft.preflightSimulation.runtimeBytes.length === 26, "runtime byte plan must contain 26 entries");
assert(Array.isArray(draft.preflightSimulation.codeHashes) && draft.preflightSimulation.codeHashes.length === 26, "runtime code-hash plan must contain 26 entries");
const runtimeCanonical = draft.contracts.map((item, index) => {
  const runtimeSize = draft.preflightSimulation.runtimeBytes[index];
  const codeHash = draft.preflightSimulation.codeHashes[index];
  assert(Number.isInteger(runtimeSize) && runtimeSize > 0, `invalid runtime size at index ${index}`);
  assert(/^0x[0-9a-fA-F]{64}$/.test(codeHash), `invalid runtime code hash at index ${index}`);
  return [index, item.role, lower(item.predictedAddress), runtimeSize, lower(codeHash)].join("|");
});
const runtimePlanHash = createHash("sha256").update(`${runtimeCanonical.join("\n")}\n`).digest("hex");
assert(draft.preflightSimulation.runtimePlanSha256 === runtimePlanHash, "runtime plan hash drifted");

const localByRole = new Map(local.contracts.map((item) => [item.role, item]));
const expectedRoles = [
  ...Array.from({ length: 22 }, (_, index) => `weightsBlob[${index}]`),
  "zhLexiconBlob", "enLexiconBlob", "modelCard", "freeChatEngine",
];
let measuredTotal = 0n;
let paddedTotal = 0n;
let plannedTotal = 0n;
const canonical = [];

for (let index = 0; index < 26; index += 1) {
  const item = draft.contracts[index];
  const transaction = run.transactions[index];
  const tx = transaction.transaction;
  const nonce = quantity(tx.nonce);
  const gas = quantity(tx.gas);
  const value = quantity(tx.value ?? "0x0");
  const chainId = quantity(tx.chainId);
  const measured = BigInt(item.measuredAnvilGas);
  const padded = BigInt(item.paddedGasLimit);
  const measuredWithBuffer = (measured * 130n + 99n) / 100n;
  const expectedPadded = measuredWithBuffer > gas ? measuredWithBuffer : gas;
  const localItem = localByRole.get(item.role);

  assert(item.role === expectedRoles[index], `role mismatch at index ${index}`);
  assert(item.nonce === index && nonce === BigInt(index), `nonce mismatch at index ${index}`);
  assert(chainId === 56n, `chain ID mismatch at index ${index}`);
  assert(lower(tx.from) === lower(draft.deployer), `sender mismatch at index ${index}`);
  assert(tx.to === null, `transaction ${index} is not a CREATE`);
  assert(value === 0n, `transaction ${index} has non-zero native value`);
  assert(typeof tx.input === "string" && /^0x[0-9a-fA-F]+$/.test(tx.input), `transaction ${index} has invalid creation calldata`);
  assert(lower(transaction.contractAddress) === lower(item.predictedAddress), `predicted address mismatch at index ${index}`);
  assert(localItem && BigInt(localItem.gasUsed) === measured, `measured local gas mismatch for ${item.role}`);
  assert(padded === expectedPadded, `buffered gas limit mismatch for ${item.role}`);
  assert(gas <= padded, `Forge gas plan is not covered by the padded limit for ${item.role}`);

  measuredTotal += measured;
  paddedTotal += padded;
  plannedTotal += gas;
  canonical.push([index, nonce, lower(tx.from), "", gas, value, lower(tx.input), lower(transaction.contractAddress)].join("|"));
}

const modelArgs = run.transactions[24].arguments;
const modelBlobArgs = typeof modelArgs?.[0] === "string" ? modelArgs[0].match(/0x[0-9a-fA-F]{40}/g) : null;
assert(run.transactions[24].contractName === "TinyAIModelCard", "transaction 24 must create TinyAIModelCard");
assert(Array.isArray(modelArgs) && modelArgs.length === 4 && modelBlobArgs?.length === 22, "model-card constructor arguments are malformed");
modelBlobArgs.forEach((address, index) => {
  assert(lower(address) === lower(draft.contracts[index].predictedAddress), `model-card blob ${index} is miswired`);
});
assert(lower(modelArgs[1]) === lower(draft.contracts[22].predictedAddress), "model-card Chinese lexicon is miswired");
assert(lower(modelArgs[2]) === lower(draft.contracts[23].predictedAddress), "model-card English lexicon is miswired");
assert(lower(modelArgs[3]) === `0x${lower(draft.model.corpusSha256)}`, "model-card corpus commitment drifted");

const chatArgs = run.transactions[25].arguments;
assert(run.transactions[25].contractName === "TinyAIChat", "transaction 25 must create TinyAIChat");
assert(Array.isArray(chatArgs) && chatArgs.length === 5, "chat constructor arguments are malformed");
assert(lower(chatArgs[0]) === lower(draft.contracts[24].predictedAddress), "chat model card is miswired");
assert(lower(chatArgs[1]) === lower(draft.constructorEconomics.paymentToken), "chat payment token differs from the draft");
assert(lower(chatArgs[2]) === lower(draft.constructorEconomics.treasury), "chat treasury differs from the draft");
assert(quantity(chatArgs[3]) === BigInt(draft.constructorEconomics.feePerChat), "chat fee differs from the draft");
assert(quantity(chatArgs[4]) === BigInt(draft.constructorEconomics.burnBps), "chat burn share differs from the draft");

const planHash = createHash("sha256").update(`${canonical.join("\n")}\n`).digest("hex");
if (process.argv.includes("--print-plan-hash")) {
  process.stdout.write(`${planHash}\n`);
  process.exit(0);
}

assert(draft.preflightSimulation.creationPlanSha256 === planHash, "chain-56 creation plan hash drifted");
assert(measuredTotal === BigInt(draft.cost.measuredDeploymentGas), "measured deployment gas total mismatch");
assert(paddedTotal === BigInt(draft.cost.paddedDeploymentGas), "padded deployment gas total mismatch");
assert(plannedTotal === BigInt(draft.preflightSimulation.estimatedGasWithForgeSafetyMultipliers), "Forge safety gas total mismatch");
assert(lower(draft.contracts[24].predictedAddress) === lower(draft.preflightSimulation.predictedModelCard), "model-card prediction mismatch");
assert(lower(draft.contracts[25].predictedAddress) === lower(draft.preflightSimulation.predictedFreeChatEngine), "chat-engine prediction mismatch");

const gasPrice = Number(draft.gasPriceWeiSnapshot);
const measuredBnb = Number(measuredTotal) * gasPrice / 1e18;
const paddedBnb = Number(paddedTotal) * gasPrice / 1e18;
const chatBnb = Number(draft.cost.measuredLocalChatGas) * gasPrice / 1e18;
assert(close(draft.cost.measuredCostAtSnapshotBNB, measuredBnb), "measured BNB cost mismatch");
assert(close(draft.cost.paddedMaximumAtSnapshotBNB, paddedBnb), "padded BNB cost mismatch");
assert(close(draft.cost.measuredChatCostAtSnapshotBNB, chatBnb), "chat BNB cost mismatch");
assert(close(draft.cost.measuredCostAtSnapshotUSD, measuredBnb * draft.bnbUsdReference, 1e-10), "measured USD cost mismatch");
assert(close(draft.cost.paddedMaximumAtSnapshotUSD, paddedBnb * draft.bnbUsdReference, 1e-10), "padded USD cost mismatch");
assert(close(draft.cost.measuredChatCostAtSnapshotUSD, chatBnb * draft.bnbUsdReference, 1e-10), "chat USD cost mismatch");
assert(close(draft.cost.balanceAfterPaddedMaximumBNB, draft.cost.deployerBalanceBNB - paddedBnb), "post-deployment balance mismatch");
assert(draft.cost.deployerBalanceBNB >= paddedBnb, "snapshot balance does not cover the padded deployment maximum");

console.log(JSON.stringify({
  ok: true,
  status: "BSC_DRAFT_EXACT_PLAN_VERIFIED",
  chainId: draft.chainId,
  deployer: draft.deployer,
  transactionCount: run.transactions.length,
  nativeValueWei: "0",
  creationPlanSha256: planHash,
  runtimePlanSha256: runtimePlanHash,
  measuredGas: measuredTotal.toString(),
  paddedGas: paddedTotal.toString(),
  forgePlannedGas: plannedTotal.toString(),
  predictedModelCard: draft.preflightSimulation.predictedModelCard,
  predictedFreeChatEngine: draft.preflightSimulation.predictedFreeChatEngine,
}, null, 2));
