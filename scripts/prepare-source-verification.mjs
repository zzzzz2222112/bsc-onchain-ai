#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  if (index === -1) return fallback;
  if (!process.argv[index + 1]) throw new Error(`${name} requires a value`);
  return process.argv[index + 1];
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const contractsDir = resolve(root, "contracts");
const manifestPath = resolve(root, argument("--manifest", "deployments/bsc-mainnet-core-draft.json"));
const runFilePath = resolve(root, argument("--run-file", "contracts/broadcast/Deploy.s.sol/56/dry-run/run-latest.json"));
const outputDir = resolve(root, argument("--output", "contracts/verification"));
const forge = process.env.FORGE || "forge";

const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const run = JSON.parse(await readFile(runFilePath, "utf8"));
assert(manifest.chainId === 56, "source-verification preparation is restricted to BSC chain 56");
assert(Array.isArray(run.transactions) && run.transactions.length === 26, "expected the exact 26-transaction deployment run");

const targets = [
  {
    slug: "model-card",
    index: 24,
    contractId: "src/TinyAIModelCard.sol:TinyAIModelCard",
    artifact: "out/TinyAIModelCard.sol/TinyAIModelCard.json",
  },
  {
    slug: "chat",
    index: 25,
    contractId: "src/TinyAIChat.sol:TinyAIChat",
    artifact: "out/TinyAIChat.sol/TinyAIChat.json",
  },
];

await mkdir(outputDir, { recursive: true });
const prepared = [];
for (const target of targets) {
  const transaction = run.transactions[target.index];
  const artifact = JSON.parse(await readFile(resolve(contractsDir, target.artifact), "utf8"));
  const creationBytecode = artifact.bytecode?.object;
  const input = transaction.transaction?.input;
  const expectedAddress = manifest.contracts[target.index].address || manifest.contracts[target.index].predictedAddress;
  assert(/^0x[0-9a-fA-F]+$/.test(creationBytecode), `${target.slug} artifact has no creation bytecode`);
  assert(/^0x[0-9a-fA-F]+$/.test(input), `${target.slug} deployment input is missing`);
  assert(input.toLowerCase().startsWith(creationBytecode.toLowerCase()), `${target.slug} creation bytecode differs from the compiled artifact`);
  assert(transaction.contractAddress.toLowerCase() === expectedAddress.toLowerCase(), `${target.slug} address differs from the manifest`);

  const constructorArgs = `0x${input.slice(creationBytecode.length)}`;
  const expectedArgsBytes = target.index === 24 ? 25 * 32 : 5 * 32;
  assert((constructorArgs.length - 2) / 2 === expectedArgsBytes, `${target.slug} constructor argument length is unexpected`);
  const standardInputRaw = execFileSync(forge, [
    "verify-contract", "--show-standard-json-input", expectedAddress, target.contractId,
  ], { cwd: contractsDir, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
  const parsedStandardInput = JSON.parse(standardInputRaw);
  assert(parsedStandardInput.settings?.optimizer?.enabled === true, `${target.slug} verification input disabled the optimizer`);
  assert(parsedStandardInput.settings?.optimizer?.runs === 20_000, `${target.slug} optimizer runs drifted`);
  assert(parsedStandardInput.settings?.viaIR === true, `${target.slug} verification input disabled via-IR`);
  assert(parsedStandardInput.settings?.evmVersion === "cancun", `${target.slug} EVM version drifted`);
  const standardInput = JSON.stringify(parsedStandardInput, null, 2);
  const argsPath = resolve(outputDir, `${target.slug}.constructor-args.txt`);
  const inputPath = resolve(outputDir, `${target.slug}.standard-input.json`);
  await writeFile(argsPath, `${constructorArgs}\n`, { mode: 0o600 });
  await writeFile(inputPath, `${standardInput}\n`, { mode: 0o600 });
  prepared.push({
    ...target,
    address: expectedAddress,
    constructorArgsPath: argsPath,
    standardInputPath: inputPath,
    constructorArgsSha256: sha256(constructorArgs),
    standardInputSha256: sha256(standardInput),
    sourceCount: Object.keys(parsedStandardInput.sources).length,
  });
}

const commandLines = prepared.map((target) => [
  "forge verify-contract",
  "  --chain 56",
  "  --verifier sourcify",
  "  --watch",
  `  --constructor-args-path ${JSON.stringify(target.constructorArgsPath)}`,
  `  ${target.address}`,
  `  ${target.contractId}`,
].join(" \\\n"));
const commands = [
  "# TinyAI BSC source-verification commands",
  "",
  "> Preparation only. Running either command submits source metadata to an external verifier and requires separate user confirmation after the contracts exist on BSC.",
  "> The twenty-two model blobs and two lexicons are raw STOP-prefixed runtime data; verify their exact code hashes with the post-deployment auditor instead of pretending they are ordinary Solidity runtimes.",
  "",
  "```bash",
  "cd contracts",
  ...commandLines.flatMap((line, index) => index === 0 ? [line] : ["", line]),
  "```",
  "",
].join("\n");
await writeFile(resolve(outputDir, "COMMANDS.md"), commands, { mode: 0o600 });

const report = {
  ok: true,
  status: "SOURCE_VERIFICATION_PREPARED_NOT_SUBMITTED",
  chainId: 56,
  deploymentStatus: manifest.status,
  manifestPath: relative(root, manifestPath),
  runFilePath: relative(root, runFilePath),
  outputDir: relative(root, outputDir),
  targets: prepared.map(({ slug, contractId, address, constructorArgsPath, standardInputPath, constructorArgsSha256, standardInputSha256, sourceCount }) => ({
    slug,
    contractId,
    address,
    constructorArgsPath: relative(root, constructorArgsPath),
    standardInputPath: relative(root, standardInputPath),
    constructorArgsSha256,
    standardInputSha256,
    sourceCount,
  })),
  boundary: "No source was submitted and no explorer or verifier state was changed.",
};
await writeFile(resolve(outputDir, "manifest.json"), `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
console.log(JSON.stringify(report, null, 2));
