/**
 * Mine a Flap Tax Token V3 CREATE2 salt whose future CA ends in 7777.
 *
 * This performs no network request and sends no transaction. Keep the resulting salt private
 * until launch protection is in place; the predicted CA itself is safe to publish.
 */
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { concat, getContractAddress, keccak256, toHex } from "viem";

const portal = process.env.FLAP_PORTAL || "0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0";
const implementation = process.env.FLAP_TAX_V3_IMPLEMENTATION || "0x024f18294970B5c76c0691b87f138A0317156422";
const suffix = "7777";
const seed = process.env.FLAP_SALT_SEED || `tinyai-${crypto.randomUUID()}`;
const outputPath = process.env.FLAP_SALT_OUTPUT;

if (!outputPath) {
  throw new Error("Set FLAP_SALT_OUTPUT to a private path outside the repository.");
}

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const fallbackRepositoryRoot = resolve(scriptDirectory, "../..");
let repositoryRoot = fallbackRepositoryRoot;
try {
  repositoryRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], {
    cwd: scriptDirectory,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
} catch {
  // Release archives may not contain .git; the project root is still protected.
}

const canonicalizeFuturePath = (target) => {
  const resolved = resolve(target);
  let ancestor = resolved;
  while (!existsSync(ancestor)) {
    const parent = dirname(ancestor);
    if (parent === ancestor) break;
    ancestor = parent;
  }
  const canonicalAncestor = realpathSync.native(ancestor);
  return resolve(canonicalAncestor, relative(ancestor, resolved));
};

const canonicalRepositoryRoot = realpathSync.native(repositoryRoot);
const resolvedOutput = canonicalizeFuturePath(outputPath);
const repositoryRelativeOutput = relative(canonicalRepositoryRoot, resolvedOutput);
const outputInsideRepository =
  repositoryRelativeOutput === "" ||
  (!isAbsolute(repositoryRelativeOutput) &&
    repositoryRelativeOutput !== ".." &&
    !repositoryRelativeOutput.startsWith(`..${sep}`));

if (outputInsideRepository) {
  throw new Error("FLAP_SALT_OUTPUT must resolve outside the Git repository.");
}

const proxyCreationCode = concat([
  "0x3d602d80600a3d3981f3363d3d373d3d3d363d73",
  implementation,
  "0x5af43d82803e903d91602b57fd5bf3",
]);
const predict = (salt) => getContractAddress({ from: portal, salt, bytecode: proxyCreationCode, opcode: "CREATE2" });

let iterations = 0;
let salt = keccak256(toHex(seed));
let address = predict(salt);
while (!address.toLowerCase().endsWith(suffix)) {
  salt = keccak256(salt);
  address = predict(salt);
  iterations += 1;
  if (iterations % 200_000 === 0) process.stderr.write(`checked ${iterations}\n`);
}

mkdirSync(dirname(resolvedOutput), { recursive: true });
writeFileSync(resolvedOutput, `${JSON.stringify({ salt, address, iterations, portal, implementation }, null, 2)}\n`, {
  encoding: "utf8",
  mode: 0o600,
  flag: "wx",
});

// The salt and output path intentionally never enter stdout/stderr.
console.log(JSON.stringify({ address, iterations, saved: true }));
