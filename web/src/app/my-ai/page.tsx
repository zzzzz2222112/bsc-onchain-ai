import type { Metadata } from "next";
import { MyAIConsole } from "@/components/my-ai-console";
import type { DeploymentConfig } from "@/lib/contracts";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "我的 AI | TinyAI Protocol",
  description: "连接钱包，查看当前地址拥有的全部 TinyAI，并进入主人专属房间。",
};

function addressOrNull(value: string | undefined): `0x${string}` | null {
  return value && /^0x[0-9a-fA-F]{40}$/.test(value) ? (value as `0x${string}`) : null;
}

export default function MyAIPage() {
  const chainId = Number(process.env.NEXT_PUBLIC_CHAIN_ID || 56);
  const config: DeploymentConfig = {
    engineVersion: 6,
    chainId,
    chainName: process.env.NEXT_PUBLIC_CHAIN_NAME || (chainId === 56 ? "BNB Smart Chain" : "Local EVM"),
    nativeSymbol: "BNB",
    explorerBaseUrl: process.env.NEXT_PUBLIC_EXPLORER_URL || (chainId === 56 ? "https://bscscan.com" : ""),
    walletRpcUrl: process.env.NEXT_PUBLIC_WALLET_RPC_URL || undefined,
    chatAddress: addressOrNull(process.env.NEXT_PUBLIC_CHAT_ADDRESS),
    protocolAddress: addressOrNull(process.env.NEXT_PUBLIC_PROTOCOL_ADDRESS),
    componentsAddress: addressOrNull(process.env.NEXT_PUBLIC_COMPONENTS_ADDRESS),
    marketAddress: addressOrNull(process.env.NEXT_PUBLIC_MARKET_ADDRESS),
    brainRegistryAddress: addressOrNull(process.env.NEXT_PUBLIC_BRAIN_REGISTRY_ADDRESS),
    protocolFromBlock: Number(process.env.NEXT_PUBLIC_PROTOCOL_FROM_BLOCK || 0),
    settlementMode: process.env.NEXT_PUBLIC_SETTLEMENT_MODE === "token" ? "token" : "native",
    paymentTokenAddress: addressOrNull(process.env.NEXT_PUBLIC_PAYMENT_TOKEN_ADDRESS),
    paymentTokenSymbol: process.env.NEXT_PUBLIC_PAYMENT_TOKEN_SYMBOL || "TINYAI",
    paymentTokenDecimals: Number(process.env.NEXT_PUBLIC_PAYMENT_TOKEN_DECIMALS || 18),
    holderVaultAddress: addressOrNull(process.env.NEXT_PUBLIC_HOLDER_VAULT_ADDRESS),
    rewardAssetSymbol: process.env.NEXT_PUBLIC_REWARD_ASSET_SYMBOL || "BNB",
    rewardAssetDecimals: Number(process.env.NEXT_PUBLIC_REWARD_ASSET_DECIMALS || 18),
    buildLabel: process.env.NEXT_PUBLIC_BUILD_LABEL || "owner dashboard",
  };
  return <MyAIConsole config={config} />;
}
