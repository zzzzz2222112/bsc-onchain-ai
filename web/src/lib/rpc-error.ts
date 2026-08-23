type RpcErrorShape = {
  code?: number | string;
  shortMessage?: string;
  message?: string;
  details?: string;
  cause?: RpcErrorShape;
};

function messages(error: unknown) {
  const value = error as RpcErrorShape | null | undefined;
  return [value?.shortMessage, value?.message, value?.details, value?.cause?.message]
    .filter((part): part is string => Boolean(part))
    .join(" ");
}

/**
 * Converts server-side RPC proxy failures into actionable UI copy.
 * Returns null for errors that belong to a component's own error handling.
 */
export function explainRpcError(error: unknown): string | null {
  const value = error as RpcErrorShape | null | undefined;
  const message = messages(error);
  const code = String(value?.code ?? "");

  if (/RPC backend is not configured/i.test(message)) {
    return "链上 RPC 后端还没有配置，请稍后再试。";
  }
  if (code === "429" || /rate limit exceeded|too many requests/i.test(message)) {
    return "链上请求过于频繁，请稍后再试。";
  }
  if (/RPC upstream unavailable|upstream.*unavailable|gateway timeout|timed? ?out|ETIMEDOUT|ECONN/i.test(message)) {
    return "Alchemy 链上节点暂时没有响应，请稍后再试。";
  }
  if (/contract call target is not allowed|target is not allowed/i.test(message)) {
    return "这个合约地址尚未加入服务器的读取白名单。";
  }
  if (/unknown rpc error|rpc request failed|failed to fetch|network request failed/i.test(message)) {
    return "链上 RPC 请求失败，请稍后再试；如果持续出现，请检查服务器的 Alchemy 配置。";
  }
  if (/fetch|network|connection/i.test(message) && !/wrong chain|chain.*mismatch/i.test(message)) {
    return "暂时无法连接链上节点，请检查网络后重试。";
  }
  return null;
}
