"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  formatUnits,
  http,
  parseAbiItem,
  type Address,
  type Hash,
} from "viem";
import { holderVaultAbi, protocolAbi, type DeploymentConfig } from "@/lib/contracts";
import { canAutoAddNetwork, switchOrAddNetwork } from "@/lib/wallet-network";
import { BrandMark } from "./brand-mark";
import { GitHubLink } from "./github-link";
import { XLink } from "./x-link";
import { WalletSelectorModal, type WalletOption, useWalletSelector } from "./wallet-selector";
import styles from "./protocol-console.module.css";
type Stage = "idle" | "connecting" | "loading" | "signing" | "confirming" | "success" | "error";
type AIState = {
  dna: Hash;
  memoryRoot: Hash;
  bornAt: bigint;
  experience: bigint;
  brainVersion: number;
  turns: number;
  skillMask: bigint;
  memoryCapacity: number;
  curiosity: number;
  empathy: number;
  humor: number;
  caution: number;
  expressionLevel: number;
  autoUpgrade: boolean;
  brainSealed: boolean;
  publicChat: boolean;
};
type AIRecord = { id: bigint; name: string; state: AIState };

const transferEvent = parseAbiItem("event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)");

function short(value?: string | null, left = 6, right = 4) {
  if (!value) return "-";
  return value.length <= left + right + 1 ? value : `${value.slice(0, left)}…${value.slice(-right)}`;
}

function explainError(error: unknown) {
  const value = error as { shortMessage?: string; message?: string; code?: number };
  if (value?.code === 4001) return "你在钱包里取消了这次操作。";
  const message = value?.shortMessage || value?.message || "操作没有完成";
  if (/wrong chain|chain.*mismatch|network/i.test(message)) return "钱包网络不匹配，请切换到 BNB Smart Chain。";
  if (/NothingToClaim/i.test(message)) return "当前没有可领取的交易税奖励。";
  if (/user rejected|denied/i.test(message)) return "你在钱包里取消了这次操作。";
  return message.split("\n")[0].slice(0, 220);
}

export function MyAIConsole({ config }: { config: DeploymentConfig }) {
  const protocolAddress = config.protocolAddress || null;
  const holderVaultAddress = config.holderVaultAddress || null;
  const rewardSymbol = config.rewardAssetSymbol || config.nativeSymbol;
  const rewardDecimals = config.rewardAssetDecimals ?? 18;
  const deployed = Boolean(protocolAddress);
  const chain = useMemo(() => defineChain({
    id: config.chainId,
    name: config.chainName,
    nativeCurrency: { name: config.nativeSymbol, symbol: config.nativeSymbol, decimals: 18 },
    rpcUrls: { default: { http: ["/api/rpc"] } },
    blockExplorers: config.explorerBaseUrl ? { default: { name: "Explorer", url: config.explorerBaseUrl } } : undefined,
  }), [config]);
  const publicClient = useMemo(() => createPublicClient({
    chain,
    transport: http("/api/rpc", { batch: { batchSize: 10, wait: 5 } }),
  }), [chain]);

  const {
    ready: walletDiscoveryReady,
    selectedId: selectedWalletId,
    selectedWallet,
    selectWallet,
    wallets,
  } = useWalletSelector();
  const walletProvider = selectedWallet?.provider || null;

  const [account, setAccount] = useState<Address | null>(null);
  const [walletChain, setWalletChain] = useState<number | null>(null);
  const [stage, setStage] = useState<Stage>("idle");
  const [error, setError] = useState("");
  const [records, setRecords] = useState<AIRecord[]>([]);
  const [claimableRewards, setClaimableRewards] = useState(0n);
  const [lastTx, setLastTx] = useState<Hash | null>(null);
  const [walletModalOpen, setWalletModalOpen] = useState(false);
  const [connectingWalletId, setConnectingWalletId] = useState<string | null>(null);

  const openWalletModal = useCallback(() => { setError(""); setWalletModalOpen(true); }, []);
  const closeWalletModal = useCallback(() => setWalletModalOpen(false), []);

  const wrongChain = account !== null && walletChain !== null && walletChain !== config.chainId;
  const switchLabel = canAutoAddNetwork(config.walletRpcUrl)
    ? `添加并切换到 ${config.chainName}`
    : `切换到 ${config.chainName}`;

  const legacyOwnedIds = useCallback(async (owner: Address) => {
    if (!protocolAddress) return [] as bigint[];
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
      const ids = [...candidates].sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
      const owners = await Promise.all(ids.map((id) => publicClient.readContract({
        address: protocolAddress,
        abi: protocolAbi,
        functionName: "ownerOf",
        args: [id],
      }).catch(() => null)));
      return ids.filter((_, index) => owners[index]?.toLowerCase() === owner.toLowerCase());
    }

    const supply = await publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "totalSupply" });
    const ids = Array.from({ length: Number(supply) }, (_, index) => BigInt(index + 1));
    const owners = await Promise.all(ids.map((id) => publicClient.readContract({
      address: protocolAddress,
      abi: protocolAbi,
      functionName: "ownerOf",
      args: [id],
    }).catch(() => null)));
    return ids.filter((_, index) => owners[index]?.toLowerCase() === owner.toLowerCase());
  }, [config.protocolFromBlock, protocolAddress, publicClient]);

  const loadOwned = useCallback(async (owner: Address | null) => {
    if (!owner || !protocolAddress) { setRecords([]); setClaimableRewards(0n); setStage("idle"); return; }
    setStage("loading");
    setError("");
    try {
      const balance = await publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "balanceOf", args: [owner] });
      if (balance === 0n) { setRecords([]); setClaimableRewards(0n); setStage("idle"); return; }

      let ids: bigint[];
      try {
        ids = [...await publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "tokensOfOwner", args: [owner] })];
      } catch {
        ids = await legacyOwnedIds(owner);
      }

      const [values, rewards] = await Promise.all([
        Promise.all(ids.map(async (id) => {
          const [name, state] = await Promise.all([
            publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "aiName", args: [id] }),
            publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "aiState", args: [id] }),
          ]);
          return { id, name, state: state as AIState };
        })),
        holderVaultAddress
          ? publicClient.readContract({ address: holderVaultAddress, abi: holderVaultAbi, functionName: "claimableMany", args: [ids] })
          : Promise.resolve(0n),
      ]);
      setRecords(values.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
      setClaimableRewards(rewards);
      setStage("idle");
    } catch (cause) {
      setRecords([]);
      setClaimableRewards(0n);
      setStage("error");
      setError(`读取你的 AI 失败：${explainError(cause)}`);
    }
  }, [holderVaultAddress, legacyOwnedIds, protocolAddress, publicClient]);

  useEffect(() => {
    const injected = walletProvider;
    if (!walletDiscoveryReady) return;
    if (!injected) {
      const task = window.setTimeout(() => { setAccount(null); setWalletChain(null); }, 0);
      return () => window.clearTimeout(task);
    }
    let cancelled = false;
    const accountsChanged = (...args: unknown[]) => setAccount(((args[0] as string[])?.[0] as Address) || null);
    const chainChanged = (...args: unknown[]) => setWalletChain(Number(BigInt(args[0] as string)));
    const disconnected = () => { setAccount(null); setWalletChain(null); };
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
    }).catch(() => { /* Disconnected state is explicit. */ });
    return () => {
      cancelled = true;
      injected.removeListener?.("accountsChanged", accountsChanged);
      injected.removeListener?.("chainChanged", chainChanged);
      injected.removeListener?.("disconnect", disconnected);
    };
  }, [walletDiscoveryReady, walletProvider]);

  useEffect(() => {
    const task = window.setTimeout(() => { void loadOwned(account); }, 0);
    return () => window.clearTimeout(task);
  }, [account, loadOwned]);

  async function connectWallet(walletOption: WalletOption) {
    const injected = walletOption.provider;
    selectWallet(walletOption);
    setError("");
    setConnectingWalletId(walletOption.id);
    setStage("connecting");
    try {
      const wallet = createWalletClient({ chain, transport: custom(injected) });
      const [selected] = await wallet.requestAddresses();
      setAccount(selected);
      setWalletChain(await wallet.getChainId());
      setStage("idle");
      setWalletModalOpen(false);
    } catch (cause) {
      setStage("error");
      setError(explainError(cause));
    } finally {
      setConnectingWalletId(null);
    }
  }

  async function switchNetwork() {
    const injected = walletProvider;
    if (!injected) return;
    setError("");
    setStage("connecting");
    try {
      setWalletChain(await switchOrAddNetwork(injected, config));
      setStage("idle");
    } catch (cause) { setStage("error"); setError(`切换网络失败：${explainError(cause)}`); }
  }

  async function claimRewards() {
    if (!account || !walletProvider || !protocolAddress || !holderVaultAddress || records.length === 0) return;
    if (wrongChain) { setStage("error"); setError(`请先切换到 ${config.chainName}。`); return; }
    setError("");
    setLastTx(null);
    setStage("signing");
    try {
      const [boundProtocol, configuredVault] = await Promise.all([
        publicClient.readContract({
          address: holderVaultAddress,
          abi: holderVaultAbi,
          functionName: "protocol",
        }),
        publicClient.readContract({
          address: protocolAddress,
          abi: protocolAbi,
          functionName: "holderVault",
        }),
      ]);
      if (boundProtocol.toLowerCase() !== protocolAddress.toLowerCase()) {
        throw new Error("页面配置的奖励 Vault 与 TinyAI Protocol 不一致。");
      }
      if (configuredVault.toLowerCase() !== holderVaultAddress.toLowerCase()) {
        throw new Error("TinyAI Protocol 绑定的奖励 Vault 与页面配置不一致。");
      }
      const wallet = createWalletClient({ account, chain, transport: custom(walletProvider) });
      const ids = records.map((record) => record.id);
      const simulation = await publicClient.simulateContract({
        account,
        address: holderVaultAddress,
        abi: holderVaultAbi,
        functionName: "claim",
        args: [ids, account],
      });
      const hash = await wallet.writeContract(simulation.request);
      setLastTx(hash);
      setStage("confirming");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash,
        confirmations: 1,
        onReplaced: ({ transaction }) => setLastTx(transaction.hash),
      });
      if (receipt.status !== "success") throw new Error("领取交易执行失败。");
      await loadOwned(account);
      setStage("success");
    } catch (cause) {
      setStage("error");
      setError(`领取失败：${explainError(cause)}`);
    }
  }

  return <main className={styles.page}>
    <header className={styles.header}>
      <Link className={styles.brand} href="/protocol"><BrandMark className={styles.mark} /><span>TinyAI Protocol</span></Link>
      <nav><Link href="/protocol">Mint</Link><Link href="/my-ai">我的 AI</Link><Link href="/market">Market</Link><GitHubLink /><XLink /><Link href="/docs">Docs</Link></nav>
      <div className={styles.walletArea}>
        <span><i className={deployed ? styles.online : styles.offline} />{config.chainName}</span>
        <button type="button" onClick={openWalletModal} disabled={stage === "connecting"}>{account ? short(account) : "连接钱包"}</button>
      </div>
    </header>

    <section className={styles.dashboardIntro}>
      <p>OWNER DASHBOARD / MY AI</p>
      <h1>你的 AI，<br />只从你的钱包进入。</h1>
      <span>连接钱包后，这里只列出当前地址真正持有的 AI。卖出后它会离开列表；买入后它会进入新主人的列表。</span>
    </section>

    {wrongChain && <section className={styles.notice} role="alert">
      <div><strong>钱包网络不匹配</strong><p>资产读取来自 {config.chainName}；进入房间并发起交易前请切换网络。</p></div>
      <button type="button" onClick={switchNetwork} disabled={stage === "connecting"}>{switchLabel}</button>
    </section>}
    {error && <section className={`${styles.status} ${styles.statusError}`} aria-live="polite"><span>{error}</span><button type="button" onClick={() => { setError(""); setStage("idle"); }}>关闭</button></section>}
    {!error && ["signing", "confirming", "success"].includes(stage) && <section className={styles.status} aria-live="polite">
      <span>{stage === "signing" ? "等待钱包确认领取…" : stage === "confirming" ? "交易已发送，等待区块确认…" : "交易税奖励已领取。"}</span>
      {lastTx && config.explorerBaseUrl && <a href={`${config.explorerBaseUrl}/tx/${lastTx}`} target="_blank" rel="noreferrer">查看交易 ↗</a>}
      {stage === "success" && <button type="button" onClick={() => setStage("idle")}>关闭</button>}
    </section>}

    <section className={styles.dashboardPanel}>
      <div className={styles.dashboardMeta}>
        <span>{account ? `当前钱包 ${short(account, 10, 6)}` : "尚未连接钱包"}</span>
        <b>{stage === "loading" ? "正在读取链上所有权…" : `拥有 ${records.length} 只 AI`}</b>
      </div>

      {holderVaultAddress && account && records.length > 0 && <section className={styles.rewardPanel}>
        <div><span>FLAP TRADE TAX / AI HOLDER REWARD</span><h2>{formatUnits(claimableRewards, rewardDecimals)} {rewardSymbol}</h2><p>每只 AI 是一个等权份额。新 AI 从诞生后开始参与；AI 转手时，尚未领取的份额会随 AI 一起转给新主人。</p></div>
        <button className={styles.primary} type="button" onClick={() => { void claimRewards(); }} disabled={claimableRewards === 0n || wrongChain || ["signing", "confirming"].includes(stage)}>领取奖励</button>
      </section>}

      {!account ? <div className={styles.emptyDashboard}><div><h2>先连接钱包</h2><p>连接只用于确认当前地址，不会自动签名，也不会自动发送交易。</p><button type="button" onClick={openWalletModal}>选择钱包</button></div></div>
        : stage === "loading" ? <div className={styles.emptyDashboard}><div><h2>正在整理你的 AI</h2><p>从链上所有权记录读取，不靠手填编号。</p></div></div>
        : records.length === 0 ? <div className={styles.emptyDashboard}><div><h2>这个钱包还没有 AI</h2><p>去 Mint 页面铸造一只，或者从市场买入一只。</p><Link href="/protocol">前往 Mint</Link></div></div>
        : <div className={styles.aiGrid}>{records.map((record) => <article className={styles.aiCard} key={record.id.toString()}>
          <div className={styles.aiCardHead}><span>AI #{record.id.toString()}</span><span className={styles.privateTag}>主人房间</span></div>
          <div className={styles.aiAvatar}>T</div>
          <div className={styles.aiIdentity}><h2>{record.name}</h2><p>Brain V{record.state.brainVersion} · {record.state.autoUpgrade ? "自动升级" : "手动升级"}</p></div>
          <div className={styles.aiTraits}><div><span>对话</span><b>{record.state.turns}</b></div><div><span>经验</span><b>{record.state.experience.toString()}</b></div><div><span>记忆槽</span><b>{record.state.memoryCapacity}</b></div></div>
          <div className={styles.aiActions}><Link href={`/ai/${record.id.toString()}`}>进入私人房间</Link><Link href="/market">市场</Link></div>
        </article>)}</div>}
    </section>

    <footer><span>TINYAI OWNER DASHBOARD</span><span>{config.buildLabel}</span><span>CURRENT OWNER CONTROLS THE ROOM</span></footer>
    <WalletSelectorModal
      open={walletModalOpen}
      ready={walletDiscoveryReady}
      wallets={wallets}
      selectedId={selectedWalletId}
      connectingId={connectingWalletId}
      error={walletModalOpen ? error : ""}
      onClose={closeWalletModal}
      onSelect={connectWallet}
    />
  </main>;
}
