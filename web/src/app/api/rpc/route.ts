import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_BODY_BYTES = 64 * 1024;
const MAX_BATCH = 20;
const MAX_LOG_SPAN = 5_000n;
const RATE_CAPACITY = 80;
const REFILL_PER_SECOND = 2;
const allowedMethods = new Set([
  "eth_blockNumber", "eth_call", "eth_chainId", "eth_estimateGas", "eth_feeHistory", "eth_gasPrice",
  "eth_getBalance", "eth_getCode", "eth_getLogs", "eth_getTransactionByHash", "eth_getTransactionReceipt",
]);

type RpcRequest = { jsonrpc?: unknown; id?: unknown; method?: unknown; params?: unknown };
type Bucket = { tokens: number; updatedAt: number };
const buckets = new Map<string, Bucket>();

function rpcError(id: unknown, code: number, message: string) {
  return { jsonrpc: "2.0", id: id ?? null, error: { code, message } };
}

function clientKey(request: NextRequest) {
  return request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    || request.headers.get("x-real-ip") || "local";
}

function consumeRateLimit(key: string, cost: number) {
  const now = Date.now();
  const current = buckets.get(key) ?? { tokens: RATE_CAPACITY, updatedAt: now };
  current.tokens = Math.min(RATE_CAPACITY, current.tokens + Math.max(0, now - current.updatedAt) / 1_000 * REFILL_PER_SECOND);
  current.updatedAt = now;
  if (current.tokens < cost) {
    buckets.set(key, current);
    return false;
  }
  current.tokens -= cost;
  buckets.set(key, current);
  if (buckets.size > 2_000) {
    for (const [candidate, value] of buckets) if (now - value.updatedAt > 15 * 60_000) buckets.delete(candidate);
  }
  return true;
}

function asHexQuantity(value: unknown): bigint | null {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]+$/.test(value)) return null;
  try { return BigInt(value); } catch { return null; }
}

function allowedContracts() {
  const configured = [process.env.NEXT_PUBLIC_CHAT_ADDRESS, ...(process.env.RPC_ALLOWED_CONTRACTS || "").split(",")];
  return new Set(configured.filter((value): value is string => Boolean(value && /^0x[0-9a-fA-F]{40}$/.test(value))).map((value) => value.toLowerCase()));
}

function validTransaction(value: unknown, contracts: Set<string>) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const tx = value as Record<string, unknown>;
  if (typeof tx.to !== "string" || !/^0x[0-9a-fA-F]{40}$/.test(tx.to)) return false;
  if (!contracts.has(tx.to.toLowerCase())) return false;
  if (tx.data !== undefined && (typeof tx.data !== "string" || !/^0x[0-9a-fA-F]*$/.test(tx.data) || tx.data.length > 65_538)) return false;
  if (tx.value !== undefined && asHexQuantity(tx.value) === null) return false;
  return true;
}

function validate(item: RpcRequest): string | null {
  if (item.jsonrpc !== "2.0" || typeof item.method !== "string") return "Malformed JSON-RPC request";
  if (!allowedMethods.has(item.method)) return "RPC method is not allowed";
  const params = Array.isArray(item.params) ? item.params : [];
  const contracts = allowedContracts();
  if ((item.method === "eth_call" || item.method === "eth_estimateGas") && !validTransaction(params[0], contracts)) return "Contract call target is not allowed";
  if (item.method === "eth_getCode" && (typeof params[0] !== "string" || !contracts.has(params[0].toLowerCase()))) return "Code target is not allowed";
  if (item.method === "eth_getLogs") {
    const filter = params[0];
    if (!filter || typeof filter !== "object" || Array.isArray(filter)) return "Invalid log filter";
    const record = filter as Record<string, unknown>;
    const addresses = Array.isArray(record.address) ? record.address : [record.address];
    if (addresses.length === 0 || addresses.some((address) => typeof address !== "string" || !contracts.has(address.toLowerCase()))) return "Log target is not allowed";
    if (record.blockHash !== undefined) return "blockHash log queries are disabled";
    const from = asHexQuantity(record.fromBlock);
    const to = asHexQuantity(record.toBlock);
    if (from === null || to === null || to < from || to - from > MAX_LOG_SPAN) return "Log range must be an explicit span of at most 5000 blocks";
  }
  if (item.method === "eth_feeHistory") {
    const count = asHexQuantity(params[0]);
    if (count === null || count > 128n) return "feeHistory block count exceeds 128";
  }
  return null;
}

function upstreamUrl() {
  if (process.env.RPC_URL) return process.env.RPC_URL;
  const key = process.env.ALCHEMY_API_KEY;
  if (!key) return null;
  const network = process.env.RPC_NETWORK || "bnb-mainnet";
  if (!/^[a-z0-9-]+$/.test(network)) return null;
  return `https://${network}.g.alchemy.com/v2/${key}`;
}

export async function POST(request: NextRequest) {
  const declaredLength = Number(request.headers.get("content-length") || 0);
  if (declaredLength > MAX_BODY_BYTES) return NextResponse.json(rpcError(null, -32600, "Request too large"), { status: 413 });
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) return NextResponse.json(rpcError(null, -32600, "Request too large"), { status: 413 });

  let payload: RpcRequest | RpcRequest[];
  try { payload = JSON.parse(raw) as RpcRequest | RpcRequest[]; }
  catch { return NextResponse.json(rpcError(null, -32700, "Invalid JSON"), { status: 400 }); }

  const items = Array.isArray(payload) ? payload : [payload];
  if (items.length === 0 || items.length > MAX_BATCH) return NextResponse.json(rpcError(null, -32600, `Batch size must be 1 to ${MAX_BATCH}`), { status: 400 });
  if (!consumeRateLimit(clientKey(request), items.length)) return NextResponse.json(rpcError(null, -32005, "Rate limit exceeded"), { status: 429 });
  for (const item of items) {
    const problem = validate(item);
    if (problem) return NextResponse.json(rpcError(item.id, -32600, problem), { status: 400 });
  }

  const url = upstreamUrl();
  if (!url) return NextResponse.json(rpcError(null, -32000, "RPC backend is not configured"), { status: 503 });
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 12_000);
    try {
      const response = await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: raw, cache: "no-store", signal: controller.signal });
      return new NextResponse(await response.text(), {
        status: response.ok ? 200 : 502,
        headers: { "content-type": "application/json", "cache-control": "no-store" },
      });
    } finally { clearTimeout(timeout); }
  } catch {
    return NextResponse.json(rpcError(null, -32000, "RPC upstream unavailable"), { status: 502 });
  }
}
