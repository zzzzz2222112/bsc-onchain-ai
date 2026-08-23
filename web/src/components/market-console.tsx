"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  formatEther,
  formatUnits,
  http,
  parseAbiItem,
  parseEther,
  parseUnits,
  type Address,
  type EIP1193Provider,
  type Hash,
} from "viem";
import { componentsAbi, marketAbi, protocolAbi, tokenAbi, tokenMarketAbi, type DeploymentConfig } from "@/lib/contracts";
import { canAutoAddNetwork, switchOrAddNetwork } from "@/lib/wallet-network";
import { GitHubLink } from "./github-link";
import styles from "./market-console.module.css";

type InjectedProvider = EIP1193Provider & {
  on?: (event: string, listener: (...args: unknown[]) => void) => void;
  removeListener?: (event: string, listener: (...args: unknown[]) => void) => void;
};
type Stage = "idle" | "connecting" | "simulating" | "signing" | "confirming" | "success" | "error";
type MarketMeta = { nextListingId: bigint };
type AIRecord = { id: bigint; owner: Address; name: string; approved: boolean };
type AIStateSummary = {
  brainVersion: number;
  turns: number;
  experience: bigint;
  curiosity: number;
  empathy: number;
  humor: number;
  caution: number;
};
type Listing = {
  id: bigint;
  seller: Address;
  asset: Address;
  tokenId: bigint;
  unitPrice: bigint;
  amount: bigint;
  assetKind: number;
  title: string;
  description: string;
  aiState?: AIStateSummary;
};
type Filter = "all" | "ai" | "component" | "mine";
type Sort = "newest" | "price-low" | "price-high";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;
const MARKET_SCAN_BATCH = 48n;
const MARKET_SCAN_ROUNDS = 3;
const transferEvent = parseAbiItem("event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)");
const components = [
  { id: 1, name: "记忆细胞", effect: "永久增加 1 个可查询记忆槽，最多 8 个。" },
  { id: 2, name: "好奇基因", effect: "永久增加 5 点好奇心。" },
  { id: 3, name: "共情基因", effect: "永久增加 5 点共情。" },
  { id: 4, name: "幽默基因", effect: "永久增加 5 点幽默。" },
  { id: 5, name: "警惕基因", effect: "永久增加 5 点警惕。" },
  { id: 6, name: "表达核心", effect: "增加回答表达变体，最多融合 2 个。" },
] as const;

function provider() {
  return (window as Window & { ethereum?: InjectedProvider }).ethereum;
}

function short(value?: string | null, left = 6, right = 4) {
  if (!value) return "-";
  return value.length <= left + right + 1 ? value : `${value.slice(0, left)}…${value.slice(-right)}`;
}

function explainError(error: unknown) {
  const value = error as { shortMessage?: string; message?: string; details?: string; code?: number; cause?: { details?: string; message?: string } };
  if (value?.code === 4001) return "你在钱包里取消了这次操作。";
  const message = value?.details || value?.cause?.details || value?.shortMessage || value?.cause?.message || value?.message || "操作没有完成";
  if (/batch size/i.test(message)) return "一次 RPC 读取数量超过代理上限，请刷新页面后重试。";
  if (/rate limit|too many requests|429/i.test(message)) return "链上读取过于集中，请稍后重试。";
  if (/ERC20InsufficientBalance|allowance|transfer amount exceeds|insufficient token/i.test(message)) return "代币余额或授权不足。";
  if (/UnsupportedPaymentToken/i.test(message)) return "这种代币的实际到账数量与标价不一致，市场拒绝成交。";
  if (/PaymentTokenNotDeployed/i.test(message)) return "结算代币尚未完成部署。";
  if (/insufficient funds/i.test(message)) return "钱包 BNB 不足，无法支付网络 Gas。";
  if (/MissingApproval/i.test(message)) return "卖家的资产授权已经失效，请刷新市场。";
  if (/InvalidListing/i.test(message)) return "这件商品已经成交、撤销或失效，请刷新市场。";
  if (/wrong chain|chain.*mismatch|network/i.test(message)) return "钱包网络不匹配，请先切换到页面显示的网络。";
  if (/user rejected|denied/i.test(message)) return "你在钱包里取消了这次操作。";
  return message.split("\n")[0].slice(0, 220);
}

function parsePositiveId(value: string, label: string) {
  if (!/^\d+$/.test(value) || BigInt(value) < 1n) throw new Error(`${label}必须是大于 0 的整数。`);
  return BigInt(value);
}

function componentInfo(id: bigint) {
  return components.find((item) => BigInt(item.id) === id);
}

function uniqueListings(items: Listing[]) {
  const byId = new Map<string, Listing>();
  items.forEach((item) => byId.set(item.id.toString(), item));
  return [...byId.values()].sort((a, b) => a.id > b.id ? -1 : a.id < b.id ? 1 : 0);
}

export function MarketConsole({ config }: { config: DeploymentConfig }) {
  const protocolAddress = config.protocolAddress || null;
  const componentsAddress = config.componentsAddress || null;
  const marketAddress = config.marketAddress || null;
  const tokenMode = config.settlementMode === "token";
  const paymentTokenAddress = config.paymentTokenAddress || null;
  const paymentSymbol = tokenMode ? (config.paymentTokenSymbol || "TOKEN") : config.nativeSymbol;
  const paymentDecimals = tokenMode ? (config.paymentTokenDecimals ?? 18) : 18;
  const activeMarketAbi = tokenMode ? tokenMarketAbi : marketAbi;
  const deployed = Boolean(protocolAddress && componentsAddress && marketAddress);
  const chain = useMemo(() => defineChain({
    id: config.chainId,
    name: config.chainName,
    nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
    rpcUrls: { default: { http: ["/api/rpc"] } },
    blockExplorers: config.explorerBaseUrl ? { default: { name: "Explorer", url: config.explorerBaseUrl } } : undefined,
  }), [config]);
  const publicClient = useMemo(() => createPublicClient({
    chain,
    transport: http("/api/rpc", { batch: { batchSize: 20, wait: 5 } }),
  }), [chain]);

  const [account, setAccount] = useState<Address | null>(null);
  const [walletChain, setWalletChain] = useState<number | null>(null);
  const [stage, setStage] = useState<Stage>("idle");
  const [action, setAction] = useState("等待操作");
  const [error, setError] = useState("");
  const [lastTx, setLastTx] = useState<Hash | null>(null);
  const [meta, setMeta] = useState<MarketMeta | null>(null);
  const [owed, setOwed] = useState(0n);
  const [paymentBalance, setPaymentBalance] = useState(0n);
  const [paymentAllowance, setPaymentAllowance] = useState(0n);

  const [aiPrice, setAiPrice] = useState(tokenMode ? "500" : "0.01");
  const [selectedAI, setSelectedAI] = useState<AIRecord | null>(null);
  const [ownedAIs, setOwnedAIs] = useState<AIRecord[]>([]);
  const [ownedAILoading, setOwnedAILoading] = useState(false);

  const [componentId, setComponentId] = useState("1");
  const [componentAmount, setComponentAmount] = useState("1");
  const [componentPrice, setComponentPrice] = useState(tokenMode ? "500" : "0.001");
  const [componentBalance, setComponentBalance] = useState(0n);
  const [componentApproved, setComponentApproved] = useState(false);

  const [listings, setListings] = useState<Listing[]>([]);
  const [listing, setListing] = useState<Listing | null>(null);
  const [purchaseAmount, setPurchaseAmount] = useState("1");
  const [marketLoading, setMarketLoading] = useState(true);
  const [marketError, setMarketError] = useState("");
  const scanCursor = useRef(1n);
  const [hasOlder, setHasOlder] = useState(false);
  const [scannedCount, setScannedCount] = useState(0);
  const [inactiveCount, setInactiveCount] = useState(0);
  const [filter, setFilter] = useState<Filter>("all");
  const [sort, setSort] = useState<Sort>("newest");
  const [search, setSearch] = useState("");

  const wrongChain = account !== null && walletChain !== null && walletChain !== config.chainId;
  const busy = !["idle", "success", "error"].includes(stage);
  const ownsSelectedAI = Boolean(account && selectedAI && selectedAI.owner.toLowerCase() === account.toLowerCase());
  const switchLabel = canAutoAddNetwork(config.walletRpcUrl)
    ? `添加并切换到 ${config.chainName}`
    : `切换到 ${config.chainName}`;
  const latestListing = meta && meta.nextListingId > 1n ? meta.nextListingId - 1n : 0n;
  const loadedAI = listings.filter((item) => item.assetKind === 1).length;
  const loadedComponents = listings.length - loadedAI;
  const formatPrice = useCallback((value: bigint) => tokenMode ? formatUnits(value, paymentDecimals) : formatEther(value), [paymentDecimals, tokenMode]);
  const parsePrice = useCallback((value: string) => tokenMode ? parseUnits(value, paymentDecimals) : parseEther(value), [paymentDecimals, tokenMode]);

  const filteredListings = useMemo(() => {
    const term = search.trim().toLowerCase().replace(/^#/, "");
    const filtered = listings.filter((item) => {
      if (filter === "ai" && item.assetKind !== 1) return false;
      if (filter === "component" && item.assetKind !== 2) return false;
      if (filter === "mine" && (!account || item.seller.toLowerCase() !== account.toLowerCase())) return false;
      if (!term) return true;
      return item.title.toLowerCase().includes(term)
        || item.id.toString() === term
        || item.tokenId.toString() === term
        || item.seller.toLowerCase().includes(term);
    });
    return filtered.sort((a, b) => {
      if (sort === "price-low") return a.unitPrice < b.unitPrice ? -1 : a.unitPrice > b.unitPrice ? 1 : 0;
      if (sort === "price-high") return a.unitPrice > b.unitPrice ? -1 : a.unitPrice < b.unitPrice ? 1 : 0;
      return a.id > b.id ? -1 : a.id < b.id ? 1 : 0;
    });
  }, [account, filter, listings, search, sort]);

  const selectedAmount = listing?.assetKind === 1
    ? 1n
    : /^\d+$/.test(purchaseAmount) && BigInt(purchaseAmount) > 0n ? BigInt(purchaseAmount) : 1n;
  const selectedTotal = listing ? listing.unitPrice * selectedAmount : 0n;

  const loadWalletState = useCallback(async (requested?: Address | null) => {
    const user = requested === undefined ? account : requested;
    if (!user || !componentsAddress || !marketAddress) {
      setOwed(0n);
      setPaymentBalance(0n);
      setPaymentAllowance(0n);
      setComponentBalance(0n);
      setComponentApproved(false);
      return;
    }
    const id = /^\d+$/.test(componentId) && BigInt(componentId) > 0n ? BigInt(componentId) : 1n;
    try {
      const [balance, approved] = await Promise.all([
        publicClient.readContract({ address: componentsAddress, abi: componentsAbi, functionName: "balanceOf", args: [user, id] }),
        publicClient.readContract({ address: componentsAddress, abi: componentsAbi, functionName: "isApprovedForAll", args: [user, marketAddress] }),
      ]);
      setComponentBalance(balance);
      setComponentApproved(approved);
      if (tokenMode) {
        if (!paymentTokenAddress) throw new Error("Token Mode 尚未配置结算代币地址。");
        const [onchainToken, tokenBalance, allowance] = await Promise.all([
          publicClient.readContract({ address: marketAddress, abi: tokenMarketAbi, functionName: "paymentToken" }),
          publicClient.readContract({ address: paymentTokenAddress, abi: tokenAbi, functionName: "balanceOf", args: [user] }),
          publicClient.readContract({ address: paymentTokenAddress, abi: tokenAbi, functionName: "allowance", args: [user, marketAddress] }),
        ]);
        if (onchainToken.toLowerCase() !== paymentTokenAddress.toLowerCase()) throw new Error("页面配置的结算代币与市场合约不一致。");
        setOwed(0n);
        setPaymentBalance(tokenBalance);
        setPaymentAllowance(allowance);
      } else {
        const currentOwed = await publicClient.readContract({ address: marketAddress, abi: marketAbi, functionName: "owed", args: [user] });
        setOwed(currentOwed);
        setPaymentBalance(0n);
        setPaymentAllowance(0n);
      }
    } catch (cause) {
      setError(`读取钱包市场状态失败：${explainError(cause)}`);
    }
  }, [account, componentId, componentsAddress, marketAddress, paymentTokenAddress, publicClient, tokenMode]);

  const loadMarketplace = useCallback(async (append = false) => {
    if (!marketAddress || !protocolAddress || !componentsAddress) {
      setMarketLoading(false);
      return;
    }
    setMarketLoading(true);
    setMarketError("");
    try {
      const [marketFeeBps, nextListingId] = await Promise.all([
        publicClient.readContract({ address: marketAddress, abi: activeMarketAbi, functionName: "MARKET_FEE_BPS" }),
        publicClient.readContract({ address: marketAddress, abi: activeMarketAbi, functionName: "nextListingId" }),
      ]);
      if (marketFeeBps !== 0) throw new Error("市场合约版本不匹配，请刷新部署配置。");
      if (tokenMode) {
        if (!paymentTokenAddress) throw new Error("Token Mode 尚未配置结算代币地址。");
        const onchainToken = await publicClient.readContract({ address: marketAddress, abi: tokenMarketAbi, functionName: "paymentToken" });
        if (onchainToken.toLowerCase() !== paymentTokenAddress.toLowerCase()) throw new Error("页面配置的结算代币与市场合约不一致。");
      }
      setMeta({ nextListingId });
      let cursor = append ? scanCursor.current : nextListingId;
      let scanned = 0;
      let inactive = 0;
      const discovered: Listing[] = [];

      for (let round = 0; round < MARKET_SCAN_ROUNDS && cursor > 1n; round += 1) {
        const end = cursor > MARKET_SCAN_BATCH + 1n ? cursor - MARKET_SCAN_BATCH : 1n;
        const ids: bigint[] = [];
        for (let id = cursor - 1n; id >= end; id -= 1n) ids.push(id);
        scanned += ids.length;
        const raw = await Promise.all(ids.map(async (id) => {
          const [seller, asset, tokenId, unitPrice, amount, assetKind] = await publicClient.readContract({
            address: marketAddress,
            abi: activeMarketAbi,
            functionName: "listings",
            args: [id],
          });
          return { id, seller, asset, tokenId, unitPrice, amount, assetKind };
        }));

        const active = raw.filter((item) => item.seller !== ZERO_ADDRESS);
        inactive += raw.length - active.length;
        const checked = await Promise.all(active.map(async (item): Promise<Listing | null> => {
          if (item.assetKind === 1) {
            if (item.asset.toLowerCase() !== protocolAddress.toLowerCase()) return null;
            try {
              const [owner, approved, operatorApproved, name, state] = await Promise.all([
                publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "ownerOf", args: [item.tokenId] }),
                publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "getApproved", args: [item.tokenId] }),
                publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "isApprovedForAll", args: [item.seller, marketAddress] }),
                publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "aiName", args: [item.tokenId] }),
                publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "aiState", args: [item.tokenId] }),
              ]);
              const authorized = approved.toLowerCase() === marketAddress.toLowerCase() || operatorApproved;
              if (owner.toLowerCase() !== item.seller.toLowerCase() || !authorized) return null;
              const summary = state as AIStateSummary;
              return {
                ...item,
                title: name,
                description: `Brain V${summary.brainVersion} · ${summary.turns} 次已保存对话 · ${summary.experience} 经验`,
                aiState: summary,
              };
            } catch { return null; }
          }
          if (item.assetKind === 2) {
            if (item.asset.toLowerCase() !== componentsAddress.toLowerCase()) return null;
            try {
              const [balance, approved] = await Promise.all([
                publicClient.readContract({ address: componentsAddress, abi: componentsAbi, functionName: "balanceOf", args: [item.seller, item.tokenId] }),
                publicClient.readContract({ address: componentsAddress, abi: componentsAbi, functionName: "isApprovedForAll", args: [item.seller, marketAddress] }),
              ]);
              if (balance < item.amount || !approved) return null;
              const info = componentInfo(item.tokenId);
              return {
                ...item,
                title: info?.name || `组件 #${item.tokenId}`,
                description: info?.effect || "可融合进 TinyAI 的链上能力组件。",
              };
            } catch { return null; }
          }
          return null;
        }));
        inactive += checked.filter((item) => item === null).length;
        discovered.push(...checked.filter((item): item is Listing => item !== null));
        cursor = end;
        if (discovered.length >= 12) break;
      }

      setListings((current) => append ? uniqueListings([...current, ...discovered]) : uniqueListings(discovered));
      scanCursor.current = cursor;
      setHasOlder(cursor > 1n);
      setScannedCount((current) => append ? current + scanned : scanned);
      setInactiveCount((current) => append ? current + inactive : inactive);
      if (!append) {
        setListing((current) => current ? discovered.find((item) => item.id === current.id) || null : null);
      }
    } catch (cause) {
      setMarketError(`市场商品读取失败：${explainError(cause)}`);
      if (!append) setListings([]);
    } finally {
      setMarketLoading(false);
    }
  }, [activeMarketAbi, componentsAddress, marketAddress, paymentTokenAddress, protocolAddress, publicClient, tokenMode]);

  const loadOwnedAIs = useCallback(async (owner: Address | null) => {
    if (!owner || !protocolAddress || !marketAddress) {
      setOwnedAIs([]);
      setSelectedAI(null);
      return;
    }
    setOwnedAILoading(true);
    setError("");
    try {
      const balance = await publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "balanceOf", args: [owner] });
      if (balance === 0n) {
        setOwnedAIs([]);
        setSelectedAI(null);
        return;
      }

      let ids: bigint[];
      try {
        ids = [...await publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "tokensOfOwner", args: [owner] })];
      } catch {
        const fromBlock = BigInt(config.protocolFromBlock || 0);
        if (fromBlock > 0n) {
          const latest = await publicClient.getBlockNumber();
          const candidates = new Set<bigint>();
          let cursor = fromBlock;
          while (cursor <= latest) {
            const toBlock = cursor + 5_000n < latest ? cursor + 5_000n : latest;
            const [incoming, outgoing] = await Promise.all([
              publicClient.getLogs({ address: protocolAddress, event: transferEvent, args: { to: owner }, fromBlock: cursor, toBlock }),
              publicClient.getLogs({ address: protocolAddress, event: transferEvent, args: { from: owner }, fromBlock: cursor, toBlock }),
            ]);
            for (const log of [...incoming, ...outgoing]) if (log.args.tokenId !== undefined) candidates.add(log.args.tokenId);
            cursor = toBlock + 1n;
          }
          const candidatesById = [...candidates].sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
          const currentOwners = await Promise.all(candidatesById.map((id) => publicClient.readContract({
            address: protocolAddress,
            abi: protocolAbi,
            functionName: "ownerOf",
            args: [id],
          }).catch(() => null)));
          ids = candidatesById.filter((_, index) => currentOwners[index]?.toLowerCase() === owner.toLowerCase());
        } else {
          const supply = await publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "totalSupply" });
          const candidatesById = Array.from({ length: Number(supply) }, (_, index) => BigInt(index + 1));
          const currentOwners = await Promise.all(candidatesById.map((id) => publicClient.readContract({
            address: protocolAddress,
            abi: protocolAbi,
            functionName: "ownerOf",
            args: [id],
          }).catch(() => null)));
          ids = candidatesById.filter((_, index) => currentOwners[index]?.toLowerCase() === owner.toLowerCase());
        }
      }

      const operatorApproved = await publicClient.readContract({
        address: protocolAddress,
        abi: protocolAbi,
        functionName: "isApprovedForAll",
        args: [owner, marketAddress],
      });
      const records = await Promise.all(ids.map(async (id) => {
        const [name, approved] = await Promise.all([
          publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "aiName", args: [id] }),
          publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "getApproved", args: [id] }),
        ]);
        return { id, owner, name, approved: operatorApproved || approved.toLowerCase() === marketAddress.toLowerCase() };
      }));
      records.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
      setOwnedAIs(records);
      setSelectedAI((current) => records.find((item) => item.id === current?.id) || records[0] || null);
    } catch (cause) {
      setOwnedAIs([]);
      setSelectedAI(null);
      setError(`读取你拥有的 AI 失败：${explainError(cause)}`);
    } finally {
      setOwnedAILoading(false);
    }
  }, [config.protocolFromBlock, marketAddress, protocolAddress, publicClient]);

  useEffect(() => {
    const task = window.setTimeout(() => { if (deployed) void loadMarketplace(false); }, 0);
    return () => window.clearTimeout(task);
  }, [deployed, loadMarketplace]);

  useEffect(() => {
    const task = window.setTimeout(() => { void loadWalletState(); }, 0);
    return () => window.clearTimeout(task);
  }, [loadWalletState]);

  useEffect(() => {
    const task = window.setTimeout(() => { void loadOwnedAIs(account); }, 0);
    return () => window.clearTimeout(task);
  }, [account, loadOwnedAIs]);

  useEffect(() => {
    const injected = provider();
    if (!injected) return;
    let cancelled = false;
    const accountsChanged = (...args: unknown[]) => {
      const accounts = args[0] as string[];
      setAccount((accounts?.[0] as Address) || null);
      setSelectedAI(null);
    };
    const chainChanged = (...args: unknown[]) => {
      setWalletChain(Number(BigInt(args[0] as string)));
      setSelectedAI(null);
    };
    const disconnected = () => {
      setAccount(null);
      setWalletChain(null);
      setSelectedAI(null);
    };
    injected.on?.("accountsChanged", accountsChanged);
    injected.on?.("chainChanged", chainChanged);
    injected.on?.("disconnect", disconnected);
    void Promise.all([
      injected.request({ method: "eth_accounts" }) as Promise<string[]>,
      injected.request({ method: "eth_chainId" }) as Promise<string>,
    ]).then(([accounts, chainId]) => {
      if (cancelled) return;
      setAccount((accounts?.[0] as Address) || null);
      setWalletChain(Number(BigInt(chainId)));
    }).catch(() => { /* Read-only market remains available. */ });
    return () => {
      cancelled = true;
      injected.removeListener?.("accountsChanged", accountsChanged);
      injected.removeListener?.("chainChanged", chainChanged);
      injected.removeListener?.("disconnect", disconnected);
    };
  }, []);

  async function connectWallet() {
    setError("");
    const injected = provider();
    if (!injected) { setError("没有检测到浏览器钱包。你仍然可以浏览全部商品。"); return; }
    setStage("connecting");
    setAction("连接钱包");
    try {
      const wallet = createWalletClient({ chain, transport: custom(injected) });
      const [selected] = await wallet.requestAddresses();
      setAccount(selected);
      setWalletChain(await wallet.getChainId());
      await loadWalletState(selected);
      setStage("idle");
    } catch (cause) { setStage("error"); setError(explainError(cause)); }
  }

  async function switchNetwork() {
    const injected = provider();
    if (!injected) return;
    setError("");
    setAction("切换钱包网络");
    setStage("connecting");
    try {
      setWalletChain(await switchOrAddNetwork(injected, { ...config, nativeSymbol: "BNB" }));
      setStage("idle");
    } catch (cause) { setStage("error"); setError(`切换网络失败：${explainError(cause)}`); }
  }

  async function transact(label: string, prepare: (wallet: ReturnType<typeof createWalletClient>, user: Address) => Promise<Hash>) {
    setError("");
    setLastTx(null);
    const injected = provider();
    if (!account || !injected) { setError("请先连接钱包。"); return null; }
    if (wrongChain) { setError(`请先切换到 ${config.chainName}。`); return null; }
    setAction(label);
    setStage("simulating");
    try {
      const wallet = createWalletClient({ account, chain, transport: custom(injected) });
      const hash = await prepare(wallet, account);
      setLastTx(hash);
      setStage("confirming");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash,
        confirmations: 1,
        onReplaced: ({ transaction }) => setLastTx(transaction.hash),
      });
      if (receipt.status !== "success") throw new Error("交易执行失败。");
      setStage("success");
      await loadWalletState(account);
      return receipt;
    } catch (cause) {
      setStage("error");
      setError(explainError(cause));
      return null;
    }
  }

  async function approveAI() {
    if (!protocolAddress || !marketAddress || !selectedAI) return;
    try {
      const aiId = selectedAI.id;
      const receipt = await transact(`授权市场转移 AI #${aiId}`, async (wallet, user) => {
        const simulation = await publicClient.simulateContract({ account: user, address: protocolAddress, abi: protocolAbi, functionName: "approve", args: [marketAddress, aiId] });
        setStage("signing");
        return wallet.writeContract(simulation.request);
      });
      if (receipt) setSelectedAI((current) => current ? { ...current, approved: true } : current);
    } catch (cause) { setError(explainError(cause)); }
  }

  async function listAI() {
    if (!protocolAddress || !marketAddress || !selectedAI) return;
    try {
      const aiId = selectedAI.id;
      const price = parsePrice(aiPrice);
      if (price < 1n) throw new Error("AI 价格必须大于 0。");
      const receipt = await transact(`上架 AI #${aiId}`, async (wallet, user) => {
        const simulation = await publicClient.simulateContract({ account: user, address: marketAddress, abi: activeMarketAbi, functionName: "listAI", args: [protocolAddress, aiId, price] });
        setStage("signing");
        return wallet.writeContract(simulation.request);
      });
      if (receipt) await Promise.all([loadMarketplace(false), loadOwnedAIs(account)]);
    } catch (cause) { setError(explainError(cause)); }
  }

  async function approveComponents() {
    if (!componentsAddress || !marketAddress) return;
    const receipt = await transact("授权市场转移组件", async (wallet, user) => {
      const simulation = await publicClient.simulateContract({ account: user, address: componentsAddress, abi: componentsAbi, functionName: "setApprovalForAll", args: [marketAddress, true] });
      setStage("signing");
      return wallet.writeContract(simulation.request);
    });
    if (receipt) setComponentApproved(true);
  }

  async function listComponents() {
    if (!componentsAddress || !marketAddress) return;
    try {
      const id = parsePositiveId(componentId, "组件编号");
      const amount = parsePositiveId(componentAmount, "出售数量");
      const price = parsePrice(componentPrice);
      if (amount > componentBalance) throw new Error("出售数量超过钱包持有数量。");
      if (price < 1n) throw new Error("组件单价必须大于 0。");
      const receipt = await transact(`上架组件 #${id}`, async (wallet, user) => {
        const simulation = await publicClient.simulateContract({ account: user, address: marketAddress, abi: activeMarketAbi, functionName: "listComponents", args: [componentsAddress, id, amount, price] });
        setStage("signing");
        return wallet.writeContract(simulation.request);
      });
      if (receipt) await loadMarketplace(false);
    } catch (cause) { setError(explainError(cause)); }
  }

  async function buyListing() {
    if (!marketAddress || !listing) return;
    try {
      const amount = listing.assetKind === 1 ? 1n : parsePositiveId(purchaseAmount, "购买数量");
      if (amount > listing.amount) throw new Error("购买数量超过挂单剩余数量。");
      const total = listing.unitPrice * amount;
      if (tokenMode) {
        if (!account || !paymentTokenAddress) throw new Error("Token Mode 尚未配置结算代币或钱包未连接。");
        if (paymentBalance < total) throw new Error(`钱包 ${paymentSymbol} 余额不足。`);
        if (paymentAllowance < total) {
          const approval = await transact(`授权 ${paymentSymbol} 支付挂单 #${listing.id}`, async (wallet, user) => {
            const simulation = await publicClient.simulateContract({ account: user, address: paymentTokenAddress, abi: tokenAbi, functionName: "approve", args: [marketAddress, total] });
            setStage("signing");
            return wallet.writeContract(simulation.request);
          });
          if (!approval) return;
          setPaymentAllowance(total);
        }
      }
      const receipt = await transact(`购买挂单 #${listing.id}`, async (wallet, user) => {
        if (tokenMode) {
          const simulation = await publicClient.simulateContract({ account: user, address: marketAddress, abi: tokenMarketAbi, functionName: "buy", args: [listing.id, amount] });
          setStage("signing");
          return wallet.writeContract(simulation.request);
        }
        const simulation = await publicClient.simulateContract({ account: user, address: marketAddress, abi: marketAbi, functionName: "buy", args: [listing.id, amount], value: total });
        setStage("signing");
        return wallet.writeContract(simulation.request);
      });
      if (receipt) { setListing(null); await loadMarketplace(false); }
    } catch (cause) { setError(explainError(cause)); }
  }

  async function cancelListing() {
    if (!marketAddress || !listing) return;
    const receipt = await transact(`撤销挂单 #${listing.id}`, async (wallet, user) => {
      const simulation = await publicClient.simulateContract({ account: user, address: marketAddress, abi: activeMarketAbi, functionName: "cancel", args: [listing.id] });
      setStage("signing");
      return wallet.writeContract(simulation.request);
    });
    if (receipt) { setListing(null); await loadMarketplace(false); }
  }

  async function withdraw() {
    if (!marketAddress) return;
    const receipt = await transact("提取市场成交款", async (wallet, user) => {
      const simulation = await publicClient.simulateContract({ account: user, address: marketAddress, abi: marketAbi, functionName: "withdraw" });
      setStage("signing");
      return wallet.writeContract(simulation.request);
    });
    if (receipt) setOwed(0n);
  }

  return <main className={styles.page}>
    <header className={styles.header}>
      <Link className={styles.brand} href="/protocol"><span className={styles.mark}>T</span><span>TinyAI Market</span></Link>
      <nav><Link href="/protocol">Mint</Link><Link href="/my-ai">我的 AI</Link><Link href="/market">Market</Link><GitHubLink /><Link href="/docs">Docs</Link></nav>
      <div className={styles.walletArea}>
        <span><i className={deployed ? styles.online : styles.offline} />{config.chainName}</span>
        <button type="button" onClick={connectWallet} disabled={stage === "connecting"}>{account ? short(account) : "连接钱包"}</button>
      </div>
    </header>

    <section className={styles.hero}>
      <div><p>TINYAI OPEN MARKET</p><h1>发现、拥有、交易，<br />链上的 AI。</h1><span>不用连接钱包也能浏览所有已载入商品。AI 和组件由卖家保管，成交时由合约完成结算与转移。</span></div>
      <dl>
        <div><dt>最新挂单编号</dt><dd>#{latestListing.toString()}</dd></div>
        <div><dt>当前载入商品</dt><dd>{listings.length}</dd></div>
        <div><dt>结算资产</dt><dd>{paymentSymbol}</dd></div>
      </dl>
    </section>

    <div className={styles.content}>
      {!deployed && <section className={styles.notice} role="status"><div><strong>当前环境没有完整市场地址</strong><p>只读界面可打开，但商品读取、挂单和购买保持禁用。</p></div></section>}
      {wrongChain && <section className={styles.notice} role="alert"><div><strong>钱包网络不匹配</strong><p>浏览商品不受影响；交易前请切换到 {config.chainName}（Chain {config.chainId}）。</p></div><button type="button" onClick={switchNetwork} disabled={busy}>{switchLabel}</button></section>}
      {(error || stage !== "idle") && <section className={`${styles.status} ${error ? styles.statusError : ""}`} aria-live="polite">
        <span>{error || `${action} · ${stage === "simulating" ? "模拟中" : stage === "signing" ? "等待钱包确认" : stage === "confirming" ? "等待区块确认" : stage === "success" ? "已完成" : "处理中"}`}</span>
        {lastTx && config.explorerBaseUrl && <a href={`${config.explorerBaseUrl}/tx/${lastTx}`} target="_blank" rel="noreferrer">查看交易</a>}
        {(error || stage === "success") && <button type="button" onClick={() => { setError(""); setStage("idle"); }}>关闭</button>}
      </section>}

      <section className={styles.marketplace} aria-labelledby="market-title">
        <header className={styles.sectionHeader}>
          <div><span>LIVE INVENTORY</span><h2 id="market-title">正在出售的商品</h2><p>页面自动读取链上有效挂单，不需要你事先知道挂单编号。</p></div>
          <button type="button" onClick={() => { void loadMarketplace(false); }} disabled={!deployed || marketLoading}>刷新链上市场</button>
        </header>

        <div className={styles.marketFacts}>
          <div><span>AI</span><b>{loadedAI}</b></div><div><span>组件</span><b>{loadedComponents}</b></div>
          <div><span>已扫描</span><b>{scannedCount}</b></div><div><span>已结束 / 失效</span><b>{inactiveCount}</b></div>
          <div><span>结算方式</span><b>{meta ? "固定价格" : "-"}</b></div>
        </div>

        <div className={styles.toolbar}>
          <div className={styles.filters} role="group" aria-label="商品类型筛选">
            {(["all", "ai", "component", "mine"] as Filter[]).map((item) => <button type="button" key={item} className={filter === item ? styles.active : ""} onClick={() => setFilter(item)}>
              {item === "all" ? "全部" : item === "ai" ? "AI" : item === "component" ? "组件" : "我的挂单"}
            </button>)}
          </div>
          <label className={styles.search}><span>搜索</span><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="名称、卖家、AI 或挂单编号" /></label>
          <label className={styles.sort}><span>排序</span><select value={sort} onChange={(event) => setSort(event.target.value as Sort)}><option value="newest">最新上架</option><option value="price-low">价格从低到高</option><option value="price-high">价格从高到低</option></select></label>
        </div>

        {marketError && <div className={styles.marketError} role="alert"><span>{marketError}</span><button type="button" onClick={() => { void loadMarketplace(false); }}>重试</button></div>}

        <div className={styles.marketLayout}>
          <div className={styles.catalog}>
            {marketLoading && listings.length === 0 ? <div className={styles.skeletonGrid} aria-label="正在读取商品">{Array.from({ length: 6 }, (_, index) => <div key={index} />)}</div>
              : filteredListings.length > 0 ? <div className={styles.productGrid}>{filteredListings.map((item) => {
                const mine = Boolean(account && account.toLowerCase() === item.seller.toLowerCase());
                return <article className={`${styles.productCard} ${listing?.id === item.id ? styles.selectedCard : ""}`} key={item.id.toString()}>
                  <div className={styles.productTop}><span>{item.assetKind === 1 ? "AI NFT" : "COMPONENT"}</span><b>ORDER #{item.id.toString()}</b></div>
                  <div className={item.assetKind === 1 ? styles.aiVisual : styles.componentVisual}>{item.assetKind === 1 ? "T" : item.tokenId.toString().padStart(2, "0")}</div>
                  <div className={styles.productTitle}><div><h3>{item.title}</h3><p>#{item.tokenId.toString()} · {short(item.seller, 8, 6)}</p></div>{mine && <span>你的挂单</span>}</div>
                  <p className={styles.productDescription}>{item.description}</p>
                  {item.aiState && <div className={styles.miniTraits}><span>好奇 {item.aiState.curiosity}</span><span>共情 {item.aiState.empathy}</span><span>幽默 {item.aiState.humor}</span></div>}
                  <div className={styles.priceRow}><div><span>{item.assetKind === 1 ? "总价" : "单价"}</span><strong>{formatPrice(item.unitPrice)} {paymentSymbol}</strong></div>{item.assetKind === 2 && <b>剩余 {item.amount.toString()}</b>}</div>
                  <div className={styles.cardActions}><button className={styles.primary} type="button" onClick={() => { setListing(item); setPurchaseAmount("1"); }}>{mine ? "管理挂单" : "查看并购买"}</button></div>
                </article>;
              })}</div>
              : <div className={styles.emptyMarket}>
                <div>T</div><h3>{filter === "mine" && !account ? "连接钱包后查看自己的挂单" : latestListing === 0n ? "市场还没有商品" : "没有符合条件的有效商品"}</h3>
                <p>{latestListing === 0n ? "第一位卖家上架 AI 或组件后，商品会自动出现在这里。" : "可以换一个筛选条件、清除搜索，或继续加载更早的挂单。"}</p>
              </div>}
            {hasOlder && <button className={styles.loadMore} type="button" onClick={() => { void loadMarketplace(true); }} disabled={marketLoading}>{marketLoading ? "正在读取…" : "加载更早的链上挂单"}</button>}
          </div>

          <aside className={styles.tradeDesk} aria-label="购买面板">
            {listing ? <>
              <div className={styles.deskHead}><span>SELECTED ORDER</span><b>#{listing.id.toString()}</b></div>
              <div className={listing.assetKind === 1 ? styles.deskAI : styles.deskComponent}>{listing.assetKind === 1 ? "T" : listing.tokenId.toString().padStart(2, "0")}</div>
              <h3>{listing.title}</h3><p>{listing.description}</p>
              <dl><div><dt>卖家</dt><dd>{short(listing.seller, 10, 8)}</dd></div><div><dt>{listing.assetKind === 1 ? "资产" : "剩余"}</dt><dd>{listing.assetKind === 1 ? `AI #${listing.tokenId}` : listing.amount.toString()}</dd></div></dl>
              {listing.assetKind === 2 && <label>购买数量<input value={purchaseAmount} onChange={(event) => setPurchaseAmount(event.target.value)} inputMode="numeric" /></label>}
              <div className={styles.deskTotal}><span>本次支付</span><strong>{formatPrice(selectedTotal)} {paymentSymbol}</strong></div>
              {account?.toLowerCase() === listing.seller.toLowerCase()
                ? <button type="button" onClick={cancelListing} disabled={wrongChain || busy}>撤销自己的挂单</button>
                : <button className={styles.primary} type="button" onClick={account ? buyListing : connectWallet} disabled={wrongChain || busy}>{account ? "确认购买" : "连接钱包购买"}</button>}
              {listing.assetKind === 1 && <small>AI 房间只对当前主人开放；购买完成后，它会自动出现在“我的 AI”。</small>}
              <small>{tokenMode ? `首次使用 ${paymentSymbol} 购买时，钱包会先请求代币授权，再请求购买确认。` : "购买前会重新模拟合约；商品已经成交、授权失效或余额不足时，交易不会发送。"}</small>
            </> : <div className={styles.deskEmpty}><span>ORDER DESK</span><div>T</div><h3>选择一件商品</h3><p>点击商品卡片里的“查看并购买”，这里会显示卖家、数量和准确的 {paymentSymbol} 总价。</p></div>}
          </aside>
        </div>
      </section>

      <details className={styles.sellerCenter}>
        <summary><div><span>SELLER CENTER</span><h2>{tokenMode ? "我要出售 / 结算规则" : "我要出售 / 管理收入"}</h2><p>出售工具放在这里，浏览市场不再被表单挡住。</p></div><b>展开工具 ＋</b></summary>
        <div className={styles.sellerGrid}>
          <article className={styles.card}>
            <header><div><span>AI NFT</span><h3>出售一只 AI</h3><p>每只 AI 都能单独定价和上架，多个 AI 互不影响。</p></div></header>
            <div className={styles.lookup}>
              <label>选择你拥有的 AI<select value={selectedAI?.id.toString() || ""} onChange={(event) => setSelectedAI(ownedAIs.find((item) => item.id === BigInt(event.target.value)) || null)} disabled={!account || ownedAILoading || ownedAIs.length === 0}>
                {ownedAIs.length === 0 ? <option value="">{account ? "当前钱包没有 AI" : "请先连接钱包"}</option> : ownedAIs.map((item) => <option value={item.id.toString()} key={item.id.toString()}>#{item.id.toString()} · {item.name}</option>)}
              </select></label>
              <button type="button" onClick={() => { void loadOwnedAIs(account); }} disabled={!account || ownedAILoading || busy}>{ownedAILoading ? "读取中" : "刷新"}</button>
            </div>
            {selectedAI ? <div className={styles.assetSummary}><div className={styles.assetMark}>T</div><div><strong>{selectedAI.name}</strong><span>#{selectedAI.id.toString()} / {short(selectedAI.owner, 10, 6)}</span></div><b>你的 AI</b></div> : <p className={styles.empty}>{account ? "当前钱包没有可出售的 AI。" : "连接钱包后会自动显示你拥有的全部 AI。"}</p>}
            <label>固定价格（{paymentSymbol}）<input value={aiPrice} onChange={(event) => setAiPrice(event.target.value)} inputMode="decimal" /></label>
            <div className={styles.actions}><button type="button" onClick={approveAI} disabled={!ownsSelectedAI || selectedAI?.approved || wrongChain || busy}>{selectedAI?.approved ? "已授权" : "授权 AI"}</button><button className={styles.primary} type="button" onClick={listAI} disabled={!ownsSelectedAI || !selectedAI?.approved || wrongChain || busy}>创建挂单</button></div>
            <small>授权与上架是两次独立确认。挂单期间 AI 仍在你的钱包里。</small>
          </article>

          <article className={styles.card}>
            <header><div><span>ERC-1155</span><h3>出售组件</h3><p>组件支持按数量出售，也允许买家部分成交。</p></div><strong className={styles.balance}>持有 {componentBalance.toString()}</strong></header>
            <label>组件<select value={componentId} onChange={(event) => setComponentId(event.target.value)}>{components.map((item) => <option key={item.id} value={item.id}>#{item.id} {item.name}</option>)}</select></label>
            <div className={styles.fieldGrid}><label>出售数量<input value={componentAmount} onChange={(event) => setComponentAmount(event.target.value)} inputMode="numeric" /></label><label>单价（{paymentSymbol}）<input value={componentPrice} onChange={(event) => setComponentPrice(event.target.value)} inputMode="decimal" /></label></div>
            <div className={styles.actions}><button type="button" onClick={approveComponents} disabled={!account || componentApproved || wrongChain || busy}>{componentApproved ? "已授权" : "授权组件"}</button><button className={styles.primary} type="button" onClick={listComponents} disabled={!account || !componentApproved || componentBalance === 0n || wrongChain || busy}>创建挂单</button></div>
            <small>组件授权覆盖你的 TinyAI 组件，可以在钱包或合约中撤销。</small>
          </article>

          <article className={`${styles.card} ${styles.settlement}`}>
            <header><div><span>SETTLEMENT</span><h3>成交款与规则</h3><p>{tokenMode ? `成交时 ${paymentSymbol} 由买家直接转给卖家，不需要再提取。` : "成交款先按地址记账，再由卖家主动提取。"}</p></div></header>
            {tokenMode ? <>
              <div className={styles.owed}><span>钱包余额</span><strong>{formatPrice(paymentBalance)} {paymentSymbol}</strong></div>
              <ul><li><span>成交款</span><b>{meta ? "直接到账" : "-"}</b></li><li><span>资产托管</span><b>不托管</b></li><li><span>流动性保证</span><b>没有</b></li></ul>
            </> : <>
              <div className={styles.owed}><span>可提取</span><strong>{formatEther(owed)} BNB</strong></div>
              <button className={styles.primary} type="button" onClick={withdraw} disabled={!account || owed === 0n || wrongChain || busy}>提取到钱包</button>
              <ul><li><span>成交款</span><b>{meta ? "卖家提取" : "-"}</b></li><li><span>资产托管</span><b>不托管</b></li><li><span>流动性保证</span><b>没有</b></li></ul>
            </>}
          </article>
        </div>
      </details>
    </div>

    <footer><span>TINYAI MARKET / {paymentSymbol} SETTLEMENT</span><span>逐批读取有效链上挂单</span><span>NON-CUSTODIAL</span></footer>
  </main>;
}
