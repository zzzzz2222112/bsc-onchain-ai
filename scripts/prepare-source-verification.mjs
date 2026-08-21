#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  if (index === -1) return fallback;
  if (!process.argv[index + 1]) throw new Error(`${name} requires a value`);
  return process.argv[index + 1];
}

function requiredArgument(name) {
  const value = argument(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const genesisRunPath = resolve(requiredArgument("--genesis-run"));
const v2RunPath = resolve(requiredArgument("--v2-run"));
const artifactRoot = resolve(requiredArgument("--artifact-root"));
const sourceRoot = resolve(requiredArgument("--source-root"));
const solc = resolve(requiredArgument("--solc"));
const outputDir = resolve(root, argument("--output", "contracts/verification"));
const runs = {
  genesis: JSON.parse(await readFile(genesisRunPath, "utf8")),
  v2: JSON.parse(await readFile(v2RunPath, "utf8")),
};

assert(runs.genesis.chain === 56 && runs.genesis.transactions?.length === 45, "expected the formal 45-transaction BSC genesis broadcast");
assert(runs.v2.chain === 56 && runs.v2.transactions?.length === 3, "expected the formal 3-transaction BSC Brain V2 broadcast");

const targets = [
  ["model-card", "genesis", 24, "src/TinyAIModelCard.sol:TinyAIModelCard"],
  ["chat-v3", "genesis", 25, "src/TinyAIChat.sol:TinyAIChat"],
  ["knowledge-v5", "genesis", 26, "src/TinyAIKnowledgeV5.sol:TinyAIKnowledgeV5"],
  ["retriever-v5", "genesis", 27, "src/TinyAIRetrieverV5.sol:TinyAIRetrieverV5"],
  ["generator-v6", "genesis", 30, "src/TinyAIGeneratorV6.sol:TinyAIGeneratorV6"],
  ["genesis-brain-v1", "genesis", 31, "src/protocol/TinyAIV6BrainEngine.sol:TinyAIV6BrainEngine"],
  ["brain-registry", "genesis", 32, "src/protocol/TinyAIBrainRegistry.sol:TinyAIBrainRegistry"],
  ["components", "genesis", 34, "src/protocol/TinyAIComponents.sol:TinyAIComponents"],
  ["protocol", "genesis", 35, "src/protocol/TinyAIProtocol.sol:TinyAIProtocol"],
  ["market", "genesis", 37, "src/protocol/TinyAIMarket.sol:TinyAIMarket"],
  ["neural-decoder-v2", "v2", 0, "src/protocol/TinyAINeuralDecoderV2.sol:TinyAINeuralDecoderV2"],
  ["brain-engine-v2", "v2", 1, "src/protocol/TinyAIBrainEngineV2.sol:TinyAIBrainEngineV2"],
].map(([slug, runKey, index, publicContractId]) => ({ slug, runKey, index, publicContractId }));

await mkdir(outputDir, { recursive: true });
const prepared = [];
for (const target of targets) {
  const transaction = runs[target.runKey].transactions[target.index];
  const [, publicContractName] = target.publicContractId.split(":");
  const artifactPath = resolve(artifactRoot, `${publicContractName}.sol`, `${publicContractName}.json`);
  const artifact = JSON.parse(await readFile(artifactPath, "utf8"));
  const metadata = typeof artifact.metadata === "string" ? JSON.parse(artifact.metadata) : artifact.metadata;
  const compilationTargets = Object.entries(metadata.settings?.compilationTarget || {});
  const exactTarget = compilationTargets.find(([, name]) => name === publicContractName);
  const creationInput = transaction.transaction?.input;
  const address = transaction.contractAddress;

  assert(transaction.transactionType === "CREATE", `${target.slug} is not a CREATE transaction`);
  assert(/^0x[0-9a-fA-F]{40}$/.test(address), `${target.slug} deployment address is missing`);
  assert(/^0x[0-9a-fA-F]+$/.test(creationInput), `${target.slug} deployment input is missing`);
  assert(exactTarget, `${target.slug} artifact metadata has no compilation target`);

  const [exactSourcePath, contractName] = exactTarget;
  const sources = {};
  for (const sourcePath of Object.keys(metadata.sources || {})) {
    const diskPath = isAbsolute(sourcePath) ? sourcePath : resolve(sourceRoot, sourcePath);
    sources[sourcePath] = { content: await readFile(diskPath, "utf8") };
  }
  const settings = {
    remappings: metadata.settings.remappings || [],
    optimizer: metadata.settings.optimizer,
    metadata: metadata.settings.metadata,
    evmVersion: metadata.settings.evmVersion,
    libraries: metadata.settings.libraries || {},
    viaIR: metadata.settings.viaIR,
    outputSelection: {
      [exactSourcePath]: {
        [contractName]: ["abi", "metadata", "evm.bytecode.object", "evm.deployedBytecode.object"],
      },
    },
  };
  const standardInputObject = { language: "Solidity", sources, settings };
  const solcRaw = execFileSync(solc, ["--standard-json"], {
    input: JSON.stringify(standardInputObject),
    encoding: "utf8",
    maxBuffer: 128 * 1024 * 1024,
  });
  const solcOutput = JSON.parse(solcRaw);
  const compilerErrors = (solcOutput.errors || []).filter((entry) => entry.severity === "error");
  assert(compilerErrors.length === 0, `${target.slug} exact standard JSON compilation failed: ${compilerErrors.map((entry) => entry.formattedMessage).join("\n")}`);
  const compiledObject = solcOutput.contracts?.[exactSourcePath]?.[contractName]?.evm?.bytecode?.object;
  const creationBytecode = `0x${compiledObject || ""}`;
  assert(/^0x[0-9a-fA-F]+$/.test(creationBytecode), `${target.slug} exact standard JSON produced no creation bytecode`);
  assert(creationBytecode.toLowerCase() === artifact.bytecode.object.toLowerCase(), `${target.slug} exact standard JSON differs from the retained compiler artifact`);
  assert(creationInput.toLowerCase().startsWith(creationBytecode.toLowerCase()), `${target.slug} creation bytecode differs from the deployed transaction`);

  const constructorArgs = `0x${creationInput.slice(creationBytecode.length)}`;
  const standardInput = JSON.stringify(standardInputObject, null, 2);
  const argsPath = resolve(outputDir, `${target.slug}.constructor-args.txt`);
  const inputPath = resolve(outputDir, `${target.slug}.standard-input.json`);
  await writeFile(argsPath, `${constructorArgs}\n`, { mode: 0o600 });
  await writeFile(inputPath, `${standardInput}\n`, { mode: 0o600 });
  prepared.push({
    ...target,
    exactContractId: `${exactSourcePath}:${contractName}`,
    address,
    transactionHash: transaction.hash,
    constructorArgsPath: argsPath,
    standardInputPath: inputPath,
    exactCompilerInputReproducesCreationBytecode: true,
    constructorArgsBytes: (constructorArgs.length - 2) / 2,
    constructorArgsSha256: sha256(constructorArgs),
    standardInputSha256: sha256(standardInput),
    sourceCount: Object.keys(sources).length,
  });
}

const report = {
  ok: true,
  status: "SOURCE_VERIFICATION_PREPARED_NOT_SUBMITTED",
  chainId: 56,
  compiler: "0.8.30+commit.73712a01",
  genesisRunFile: relative(root, genesisRunPath),
  v2RunFile: relative(root, v2RunPath),
  outputDir: relative(root, outputDir),
  targets: prepared.map(({ slug, publicContractId, exactContractId, address, transactionHash, constructorArgsPath, standardInputPath, exactCompilerInputReproducesCreationBytecode, constructorArgsBytes, constructorArgsSha256, standardInputSha256, sourceCount }) => ({
    slug,
    publicContractId,
    exactContractId,
    address,
    transactionHash,
    constructorArgsPath: relative(root, constructorArgsPath),
    standardInputPath: relative(root, standardInputPath),
    exactCompilerInputReproducesCreationBytecode,
    constructorArgsBytes,
    constructorArgsSha256,
    standardInputSha256,
    sourceCount,
  })),
  boundary: "No source was submitted and no explorer or verifier state was changed.",
};
await writeFile(resolve(outputDir, "manifest.json"), `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
console.log(JSON.stringify(report, null, 2));
