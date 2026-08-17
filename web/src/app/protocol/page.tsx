import { MintConsole } from "@/components/mint-console";
import type { DeploymentConfig } from "@/lib/contracts";

export const dynamic = "force-dynamic";

function addressOrNull(value: string | undefined): `0x${string}` | null {
  return value && /^0x[0-9a-fA-F]{40}$/.test(value) ? (value as `0x${string}`) : null;
}

export default function ProtocolPage() {
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
    buildLabel: process.env.NEXT_PUBLIC_BUILD_LABEL || "protocol research build",
  };
  return <MintConsole config={config} />;
}
