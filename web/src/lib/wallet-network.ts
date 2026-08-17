import { toHex, type EIP1193Provider } from "viem";
import type { DeploymentConfig } from "@/lib/contracts";

type ProviderError = {
  code?: number;
  message?: string;
  data?: { originalError?: { code?: number; message?: string } };
};

function missingChain(error: unknown) {
  const value = error as ProviderError;
  const code = value?.code ?? value?.data?.originalError?.code;
  const message = `${value?.message || ""} ${value?.data?.originalError?.message || ""}`;
  return code === 4902 || /unknown chain|unrecognized chain|chain.*not (added|found)|network.*not (added|found)/i.test(message);
}

export function canAutoAddNetwork(walletRpcUrl?: string) {
  if (!walletRpcUrl) return false;
  try {
    return new URL(walletRpcUrl).protocol === "https:";
  } catch {
    return false;
  }
}

function missingNetworkMessage(config: DeploymentConfig) {
  if (config.walletRpcUrl?.startsWith("http://")) {
    return `钱包里没有 ${config.chainName}。请先在钱包中启用测试网络里的 Localhost 8545，再回来点击切换；钱包安全规则不允许网页自动添加 HTTP 本地 RPC。`;
  }
  return `钱包里还没有 ${config.chainName}，而页面没有配置可安全添加的 HTTPS 钱包 RPC。`;
}

export async function switchOrAddNetwork(provider: EIP1193Provider, config: DeploymentConfig) {
  const chainId = toHex(config.chainId);
  try {
    await provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId }] });
  } catch (cause) {
    if (!missingChain(cause)) throw cause;
    const walletRpcUrl = config.walletRpcUrl;
    if (!walletRpcUrl || !canAutoAddNetwork(walletRpcUrl)) {
      throw new Error(missingNetworkMessage(config));
    }
    await provider.request({
      method: "wallet_addEthereumChain",
      params: [{
        chainId,
        chainName: config.chainName,
        nativeCurrency: { name: config.nativeSymbol, symbol: config.nativeSymbol, decimals: 18 },
        rpcUrls: [walletRpcUrl],
        ...(config.explorerBaseUrl ? { blockExplorerUrls: [config.explorerBaseUrl] } : {}),
      }],
    });
    await provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId }] });
  }

  const current = await provider.request({ method: "eth_chainId" }) as string;
  return Number(BigInt(current));
}
