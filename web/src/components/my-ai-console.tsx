"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  http,
  parseAbiItem,
  type Address,
  type EIP1193Provider,
  type Hash,
} from "viem";
import { protocolAbi, type DeploymentConfig } from "@/lib/contracts";
import { canAutoAddNetwork, switchOrAddNetwork } from "@/lib/wallet-network";
import { GitHubLink } from "./github-link";
import styles from "./protocol-console.module.css";

type InjectedProvider = EIP1193Provider & {
  on?: (event: string, listener: (...args: unknown[]) => void) => void;
  removeListener?: (event: string, listener: (...args: unknown[]) => void) => void;
};
type Stage = "idle" | "connecting" | "loading" | "error";
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

function provider() {
  return (window as Window & { ethereum?: InjectedProvider }).ethereum;
}

function short(value?: string | null, left = 6, right = 4) {
  if (!value) return "-";
  return value.length <= left + right + 1 ? value : `${value.slice(0, left)}…${value.slice(-right)}`;
}

function explainError(error: unknown) {
  const value = error as { shortMessage?: string; message?: string; code?: number };
  if (value?.code === 4001) return "你在钱包里取消了这次操作。";
  const message = value?.shortMessage || value?.message || "操作没有完成";
  if (/wrong chain|chain.*mismatch|network/i.test(message)) return "钱包网络不匹配，请切换到 BNB Smart Chain。";
  if (/user rejected|denied/i.test(message)) return "你在钱包里取消了这次操作。";
  return message.split("\n")[0].slice(0, 220);
}

export function MyAIConsole({ config }: { config: DeploymentConfig }) {
  const protocolAddress = config.protocolAddress || null;
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

  const [account, setAccount] = useState<Address | null>(null);
  const [walletChain, setWalletChain] = useState<number | null>(null);
  const [stage, setStage] = useState<Stage>("idle");
  const [error, setError] = useState("");
  const [records, setRecords] = useState<AIRecord[]>([]);

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
    if (!owner || !protocolAddress) { setRecords([]); setStage("idle"); return; }
    setStage("loading");
    setError("");
    try {
      const balance = await publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "balanceOf", args: [owner] });
      if (balance === 0n) { setRecords([]); setStage("idle"); return; }

      let ids: bigint[];
      try {
        ids = [...await publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "tokensOfOwner", args: [owner] })];
      } catch {
        ids = await legacyOwnedIds(owner);
      }

      const values = await Promise.all(ids.map(async (id) => {
        const [name, state] = await Promise.all([
          publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "aiName", args: [id] }),
          publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "aiState", args: [id] }),
        ]);
        return { id, name, state: state as AIState };
      }));
      setRecords(values.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
      setStage("idle");
    } catch (cause) {
      setRecords([]);
      setStage("error");
      setError(`读取你的 AI 失败：${explainError(cause)}`);
    }
  }, [legacyOwnedIds, protocolAddress, publicClient]);

  useEffect(() => {
    const injected = provider();
    if (!injected) return;
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
  }, []);

  useEffect(() => {
    const task = window.setTimeout(() => { void loadOwned(account); }, 0);
    return () => window.clearTimeout(task);
  }, [account, loadOwned]);

  async function connectWallet() {
    const injected = provider();
    setError("");
    if (!injected) { setStage("error"); setError("没有检测到浏览器钱包。安装或打开钱包扩展后再连接。"); return; }
    setStage("connecting");
    try {
      const wallet = createWalletClient({ chain, transport: custom(injected) });
      const [selected] = await wallet.requestAddresses();
      setAccount(selected);
      setWalletChain(await wallet.getChainId());
      setStage("idle");
    } catch (cause) { setStage("error"); setError(explainError(cause)); }
  }

  async function switchNetwork() {
    const injected = provider();
    if (!injected) return;
    setError("");
    setStage("connecting");
    try {
      setWalletChain(await switchOrAddNetwork(injected, config));
      setStage("idle");
    } catch (cause) { setStage("error"); setError(`切换网络失败：${explainError(cause)}`); }
  }

  return <main className={styles.page}>
    <header className={styles.header}>
      <Link className={styles.brand} href="/protocol"><span className={styles.mark}>T</span><span>TinyAI Protocol</span></Link>
      <nav><Link href="/protocol">Mint</Link><Link href="/my-ai">我的 AI</Link><Link href="/market">Market</Link><GitHubLink /><Link href="/docs">Docs</Link></nav>
      <div className={styles.walletArea}>
        <span><i className={deployed ? styles.online : styles.offline} />{config.chainName}</span>
        <button type="button" onClick={connectWallet} disabled={stage === "connecting"}>{account ? short(account) : "连接钱包"}</button>
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

    <section className={styles.dashboardPanel}>
      <div className={styles.dashboardMeta}>
        <span>{account ? `当前钱包 ${short(account, 10, 6)}` : "尚未连接钱包"}</span>
        <b>{stage === "loading" ? "正在读取链上所有权…" : `拥有 ${records.length} 只 AI`}</b>
      </div>

      {!account ? <div className={styles.emptyDashboard}><div><h2>先连接钱包</h2><p>连接只用于确认当前地址，不会自动签名，也不会自动发送交易。</p><button type="button" onClick={connectWallet}>连接钱包</button></div></div>
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
  </main>;
}
