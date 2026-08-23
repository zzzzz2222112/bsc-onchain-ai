"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  decodeEventLog,
  defineChain,
  formatEther,
  formatUnits,
  http,
  keccak256,
  toBytes,
  type Address,
  type Hash,
} from "viem";
import { brainRegistryAbi, componentsAbi, protocolAbi, tokenAbi, tokenComponentsMintAbi, tokenProtocolMintAbi, type DeploymentConfig } from "@/lib/contracts";
import { componentCards } from "@/lib/component-catalog";
import { explainRpcError } from "@/lib/rpc-error";
import { canAutoAddNetwork, switchOrAddNetwork } from "@/lib/wallet-network";
import { BrandMark } from "./brand-mark";
import { GitHubLink } from "./github-link";
import { XLink } from "./x-link";
import { WalletSelectorModal, type WalletOption, useWalletSelector } from "./wallet-selector";
import styles from "./protocol-console.module.css";

type Stage = "idle" | "connecting" | "simulating" | "signing" | "confirming" | "success" | "error";
type Definition = {
  effectKind: number;
  slot: number;
  power: number;
  cap: bigint;
  minted: bigint;
  mintPrice: bigint;
  publicMintEnabled: boolean;
  exists: boolean;
};
type ProtocolMeta = {
  totalSupply: bigint;
  maxSupply: bigint;
  mintPrice: bigint;
  componentTotalMinted: bigint;
  componentMaxSupply: bigint;
  catalogSealed: boolean;
  recommendedVersion: number;
  versionLabel: string;
  definitions: Record<number, Definition>;
};

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;

function short(value?: string | null, left = 6, right = 4) {
  if (!value) return "-";
  return value.length <= left + right + 1 ? value : `${value.slice(0, left)}…${value.slice(-right)}`;
}

function explainError(error: unknown) {
  const value = error as { shortMessage?: string; message?: string; code?: number };
  const rpcMessage = explainRpcError(error);
  if (rpcMessage) return rpcMessage;
  if (value?.code === 4001) return "你在钱包里取消了这次操作。";
  const message = value?.shortMessage || value?.message || "操作没有完成";
  if (/ERC20InsufficientBalance|allowance|transfer amount exceeds|insufficient token/i.test(message)) return "代币余额或授权不足。";
  if (/insufficient funds/i.test(message)) return "钱包 BNB 不足，无法支付网络 Gas。";
  if (/AISupplyCapReached/i.test(message)) return "10,000 只 TinyAI 已全部诞生。";
  if (/SupplyCapExceeded/i.test(message)) return "这种组件已经达到永久发行上限。";
  if (/wrong chain|chain.*mismatch|network/i.test(message)) return "钱包网络不匹配，请先切换到 BNB Smart Chain。";
  if (/user rejected|denied/i.test(message)) return "你在钱包里取消了这次操作。";
  return message.split("\n")[0].slice(0, 220);
}

export function MintConsole({ config }: { config: DeploymentConfig }) {
  const protocolAddress = config.protocolAddress || null;
  const componentsAddress = config.componentsAddress || null;
  const registryAddress = config.brainRegistryAddress || null;
  const tokenMode = config.settlementMode === "token";
  const paymentTokenAddress = config.paymentTokenAddress || null;
  const paymentSymbol = tokenMode ? (config.paymentTokenSymbol || "TOKEN") : config.nativeSymbol;
  const paymentDecimals = tokenMode ? (config.paymentTokenDecimals ?? 18) : 18;
  const deployed = Boolean(protocolAddress && componentsAddress && registryAddress);
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
  const [action, setAction] = useState("等待操作");
  const [error, setError] = useState("");
  const [lastTx, setLastTx] = useState<Hash | null>(null);
  const [meta, setMeta] = useState<ProtocolMeta | null>(null);
  const [paymentTokenLive, setPaymentTokenLive] = useState(!tokenMode);
  const [componentBalances, setComponentBalances] = useState<Record<number, bigint>>({});
  const [name, setName] = useState("");
  const [autoUpgrade, setAutoUpgrade] = useState(true);
  const [lastMintedAI, setLastMintedAI] = useState<{ id: bigint; name: string } | null>(null);
  const [walletModalOpen, setWalletModalOpen] = useState(false);
  const [connectingWalletId, setConnectingWalletId] = useState<string | null>(null);

  const openWalletModal = useCallback(() => { setError(""); setWalletModalOpen(true); }, []);
  const closeWalletModal = useCallback(() => setWalletModalOpen(false), []);

  const wrongChain = account !== null && walletChain !== null && walletChain !== config.chainId;
  const busy = !["idle", "success", "error"].includes(stage);
  const switchLabel = canAutoAddNetwork(config.walletRpcUrl)
    ? `添加并切换到 ${config.chainName}`
    : `切换到 ${config.chainName}`;
  const formatPrice = useCallback((value: bigint) => tokenMode ? formatUnits(value, paymentDecimals) : formatEther(value), [paymentDecimals, tokenMode]);

  const loadMeta = useCallback(async () => {
    if (!protocolAddress || !componentsAddress || !registryAddress) return;
    try {
      const [totalSupply, maxSupply, mintPrice, componentTotalMinted, componentMaxSupply, catalogSealed, recommendedVersion] = await Promise.all([
        publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "totalSupply" }),
        publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "MAX_AI_SUPPLY" }),
        publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "mintPrice" }),
        publicClient.readContract({ address: componentsAddress, abi: componentsAbi, functionName: "totalMinted" }),
        publicClient.readContract({ address: componentsAddress, abi: componentsAbi, functionName: "MAX_COMPONENT_SUPPLY" }),
        publicClient.readContract({ address: componentsAddress, abi: componentsAbi, functionName: "catalogSealed" }),
        publicClient.readContract({ address: registryAddress, abi: brainRegistryAbi, functionName: "recommendedVersion" }),
      ]);
      const [release, definitions] = await Promise.all([
        publicClient.readContract({ address: registryAddress, abi: brainRegistryAbi, functionName: "versionInfo", args: [recommendedVersion] }),
        Promise.all(componentCards.map(({ id }) => publicClient.readContract({
          address: componentsAddress,
          abi: componentsAbi,
          functionName: "definition",
          args: [BigInt(id)],
        }))),
      ]);
      const byId: Record<number, Definition> = {};
      definitions.forEach((definition, index) => { byId[componentCards[index].id] = definition as Definition; });
      setMeta({
        totalSupply,
        maxSupply,
        mintPrice,
        componentTotalMinted,
        componentMaxSupply,
        catalogSealed,
        recommendedVersion,
        versionLabel: release.label,
        definitions: byId,
      });
    } catch (cause) {
      setError(`读取铸造状态失败：${explainError(cause)}`);
    }
  }, [componentsAddress, protocolAddress, publicClient, registryAddress]);

  const loadBalances = useCallback(async (owner: Address | null) => {
    if (!owner || !componentsAddress) { setComponentBalances({}); return; }
    try {
      const values = await Promise.all(componentCards.map(({ id }) => publicClient.readContract({
        address: componentsAddress,
        abi: componentsAbi,
        functionName: "balanceOf",
        args: [owner, BigInt(id)],
      })));
      const balances: Record<number, bigint> = {};
      values.forEach((balance, index) => { balances[componentCards[index].id] = balance; });
      setComponentBalances(balances);
    } catch (cause) {
      setError(`读取组件余额失败：${explainError(cause)}`);
    }
  }, [componentsAddress, publicClient]);

  useEffect(() => {
    const task = window.setTimeout(() => { if (deployed) void loadMeta(); }, 0);
    return () => window.clearTimeout(task);
  }, [deployed, loadMeta]);

  useEffect(() => {
    if (!tokenMode || !paymentTokenAddress) return;
    let cancelled = false;
    void publicClient.getCode({ address: paymentTokenAddress }).then((code) => {
      if (!cancelled) setPaymentTokenLive(Boolean(code && code !== "0x"));
    }).catch(() => {
      if (!cancelled) setPaymentTokenLive(false);
    });
    return () => { cancelled = true; };
  }, [paymentTokenAddress, publicClient, tokenMode]);

  useEffect(() => {
    const task = window.setTimeout(() => { void loadBalances(account); }, 0);
    return () => window.clearTimeout(task);
  }, [account, loadBalances]);

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
    }).catch(() => { /* Disconnected state is explicit in the UI. */ });
    return () => {
      cancelled = true;
      injected.removeListener?.("accountsChanged", accountsChanged);
      injected.removeListener?.("chainChanged", chainChanged);
      injected.removeListener?.("disconnect", disconnected);
    };
  }, [walletDiscoveryReady, walletProvider]);

  async function connectWallet(walletOption: WalletOption) {
    const injected = walletOption.provider;
    selectWallet(walletOption);
    setError("");
    setConnectingWalletId(walletOption.id);
    setStage("connecting");
    setAction("连接钱包");
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
    if (!walletProvider) return;
    setError("");
    setAction("切换钱包网络");
    setStage("connecting");
    try {
      setWalletChain(await switchOrAddNetwork(walletProvider, config));
      setStage("idle");
    } catch (cause) {
      setStage("error");
      setError(`切换网络失败：${explainError(cause)}`);
    }
  }

  async function transact(label: string, prepare: (wallet: ReturnType<typeof createWalletClient>, user: Address) => Promise<Hash>) {
    setError("");
    setLastTx(null);
    if (!account || !walletProvider) { setStage("error"); setError("请先连接钱包。"); return null; }
    if (wrongChain) { setStage("error"); setError(`请先切换到 ${config.chainName}。`); return null; }
    setAction(label);
    setStage("simulating");
    try {
      const wallet = createWalletClient({ account, chain, transport: custom(walletProvider) });
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
      await loadMeta();
      return receipt;
    } catch (cause) {
      setStage("error");
      setError(explainError(cause));
      return null;
    }
  }

  async function ensureTokenAllowance(spender: Address, amount: bigint, label: string) {
    if (!tokenMode) return true;
    if (!paymentTokenAddress) {
      setStage("error");
      setError("Token Mode 尚未配置结算代币地址。");
      return false;
    }
    if (!account) {
      setStage("error");
      setError("请先连接钱包。");
      return false;
    }
    const [onchainToken, allowance] = await Promise.all([
      publicClient.readContract({ address: spender, abi: protocolAbi, functionName: "paymentToken" }),
      publicClient.readContract({
        address: paymentTokenAddress,
        abi: tokenAbi,
        functionName: "allowance",
        args: [account, spender],
      }),
    ]);
    if (onchainToken.toLowerCase() !== paymentTokenAddress.toLowerCase()) {
      setStage("error");
      setError("页面配置的结算代币与 Mint 合约不一致。");
      return false;
    }
    if (allowance >= amount) return true;
    const receipt = await transact(label, async (wallet, user) => {
      const simulation = await publicClient.simulateContract({
        account: user,
        address: paymentTokenAddress,
        abi: tokenAbi,
        functionName: "approve",
        args: [spender, amount],
      });
      setStage("signing");
      return wallet.writeContract(simulation.request);
    });
    return Boolean(receipt);
  }

  async function mintAI(event: FormEvent) {
    event.preventDefault();
    if (!protocolAddress || !meta) return;
    const mintedName = name.trim();
    if (!mintedName) { setStage("error"); setError("先给这只 AI 起一个名字。"); return; }
    const seed = keccak256(toBytes(`${account || ZERO_ADDRESS}:${mintedName}:${crypto.randomUUID()}`));
    if (!(await ensureTokenAllowance(protocolAddress, meta.mintPrice, `授权 ${paymentSymbol} Mint AI`))) return;
    const receipt = await transact("Mint 一只新 AI", async (wallet, user) => {
      if (tokenMode) {
        const simulation = await publicClient.simulateContract({ account: user, address: protocolAddress, abi: tokenProtocolMintAbi, functionName: "mintAI", args: [mintedName, seed, autoUpgrade] });
        setStage("signing");
        return wallet.writeContract(simulation.request);
      }
      const simulation = await publicClient.simulateContract({ account: user, address: protocolAddress, abi: protocolAbi, functionName: "mintAI", args: [mintedName, seed, autoUpgrade], value: meta.mintPrice });
      setStage("signing");
      return wallet.writeContract(simulation.request);
    });
    if (!receipt) return;
    for (const log of receipt.logs) {
      try {
        const decoded = decodeEventLog({ abi: protocolAbi, data: log.data, topics: log.topics });
        if (decoded.eventName !== "AIBorn") continue;
        setLastMintedAI({ id: decoded.args.aiId, name: mintedName });
        setName("");
        break;
      } catch { /* Other receipt logs are expected. */ }
    }
  }

  async function mintComponent(componentId: number) {
    if (!componentsAddress || !meta) return;
    const definition = meta.definitions[componentId];
    if (!(await ensureTokenAllowance(componentsAddress, definition.mintPrice, `授权 ${paymentSymbol} Mint 组件`))) return;
    const receipt = await transact(`Mint ${componentCards.find((item) => item.id === componentId)?.name}`, async (wallet, user) => {
      if (tokenMode) {
        const simulation = await publicClient.simulateContract({ account: user, address: componentsAddress, abi: tokenComponentsMintAbi, functionName: "publicMint", args: [BigInt(componentId), 1n] });
        setStage("signing");
        return wallet.writeContract(simulation.request);
      }
      const simulation = await publicClient.simulateContract({ account: user, address: componentsAddress, abi: componentsAbi, functionName: "publicMint", args: [BigInt(componentId), 1n], value: definition.mintPrice });
      setStage("signing");
      return wallet.writeContract(simulation.request);
    });
    if (receipt) await loadBalances(account);
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

    <section className={styles.intro}>
      <p>ON-CHAIN LIFE PROTOCOL / MINT</p>
      <h1>铸造你的 AI，<br />以及真正有用的组件。</h1>
      <div className={styles.stats}>
        <div><span>AI 供应</span><strong>{meta ? `${meta.totalSupply.toString()} / ${meta.maxSupply.toLocaleString()}` : "-"}</strong></div>
        <div><span>推荐大脑</span><strong>{meta ? `V${meta.recommendedVersion}` : "-"}</strong></div>
        <div><span>组件供应</span><strong>{meta ? `${meta.componentTotalMinted.toString()} / ${meta.componentMaxSupply.toLocaleString()}` : "-"}</strong></div>
      </div>
    </section>

    {!deployed && <section className={styles.notice} role="status"><strong>当前环境没有完整协议地址，Mint 已禁用。</strong></section>}
    {tokenMode && <section className={styles.notice} aria-label="TINYAI 发币参数">
      <div><strong>TinyAI / TINYAI</strong><p>以 NVDAB 为 Flap 报价资产；买入税 1%，卖出税 1%，从发币交易起持续 30 天。AI 与单个组件均固定为 500 TINYAI。</p></div>
    </section>}
    {tokenMode && !paymentTokenLive && <section className={styles.notice} role="status">
      <div><strong>Token Mode 协议已预部署，TINYAI 尚未创建</strong><p>合约地址和绑定已公开，但代币 CA 目前没有运行时代码。Mint 与代币市场操作会保持禁用，最终发币完成后刷新页面即可自动启用。</p></div>
    </section>}
    {wrongChain && <section className={styles.notice} role="alert">
      <div><strong>钱包网络不匹配</strong><p>钱包当前是 Chain {walletChain}，Mint 使用 {config.chainName}（Chain {config.chainId}）。</p></div>
      <button type="button" onClick={switchNetwork} disabled={busy}>{switchLabel}</button>
    </section>}
    {(error || stage !== "idle") && <section className={`${styles.status} ${error ? styles.statusError : ""}`} aria-live="polite">
      <span>{error || `${action} · ${stage === "simulating" ? "模拟中" : stage === "signing" ? "等待钱包确认" : stage === "confirming" ? "等待区块确认" : stage === "success" ? "已完成" : "处理中"}`}</span>
      {lastTx && config.explorerBaseUrl && <a href={`${config.explorerBaseUrl}/tx/${lastTx}`} target="_blank" rel="noreferrer">查看交易 ↗</a>}
      {(error || stage === "success") && <button type="button" onClick={() => { setError(""); setStage("idle"); }}>关闭</button>}
    </section>}

    <div className={styles.grid}>
      <section className={styles.card}>
        <div className={styles.cardHead}><span>01</span><div><h2>Mint AI</h2><p>每只 AI 都有独立编号、DNA、性格、记忆和大脑版本。</p></div></div>
        <form className={styles.form} onSubmit={mintAI}>
          <label>名字<input value={name} onChange={(event) => setName(event.target.value)} placeholder="例如 MOMO" maxLength={20} /></label>
          <label className={styles.check}><input type="checkbox" checked={autoUpgrade} onChange={(event) => setAutoUpgrade(event.target.checked)} />未来发布更强大脑时自动升级</label>
          <button className={styles.primary} type="submit" disabled={!deployed || !paymentTokenLive || busy || !account || wrongChain || !meta || meta.totalSupply >= meta.maxSupply}>
            {!paymentTokenLive ? "等待 TINYAI 上线" : !account ? "先连接钱包" : meta && meta.totalSupply >= meta.maxSupply ? "10,000 只已全部 Mint" : `Mint AI · ${meta ? formatPrice(meta.mintPrice) : "-"} ${paymentSymbol}`}
          </button>
          <small>不限每个钱包的数量。Mint 完成后，到“我的 AI”查看你拥有的全部 AI。{tokenMode && config.holderVaultAddress ? " 每只 AI 同时对应一个新币交易税奖励份额。" : ""}</small>
        </form>
      </section>

      <section className={styles.card}>
        <div className={styles.cardHead}><span>02</span><div><h2>铸造完成后</h2><p>房间和融合都属于具体 AI，不在 Mint 页面混用。</p></div></div>
        {lastMintedAI ? <div className={styles.identity}>
          <div className={styles.avatar}>T<span>#{lastMintedAI.id.toString()}</span></div>
          <div><h3>{lastMintedAI.name}</h3><p>AI #{lastMintedAI.id.toString()} 已归入当前钱包</p></div>
          <em>Mint 成功</em>
        </div> : <p className={styles.empty}>连接钱包并 Mint；一只钱包可以拥有多只 AI。</p>}
        <Link className={styles.chatRoomLink} href="/my-ai"><span>查看当前钱包拥有的全部 AI</span><b>MY AI →</b></Link>
      </section>
    </div>

    <section className={styles.card}>
      <div className={styles.cardHead}><span>03</span><div><h2>Mint 组件</h2><p>这里只铸造组件。进入某只自己的 AI 房间后，再把组件融合给那一只 AI。</p></div><Link className={styles.marketLink} href="/market">进入组件市场</Link></div>
      <div className={styles.componentGrid}>{componentCards.map((item) => {
        const definition = meta?.definitions[item.id];
        const balance = componentBalances[item.id] || 0n;
        return <article key={item.id}>
          <div><b>0{item.id}</b><span>钱包持有 {balance.toString()}</span></div>
          <h3>{item.name}</h3><p>{item.effect}</p>
          <small>{definition ? `${formatPrice(definition.mintPrice)} ${paymentSymbol} · ${definition.minted}/${definition.cap}` : "读取中"}</small>
          <div><button className={styles.primary} type="button" onClick={() => { void mintComponent(item.id); }} disabled={!paymentTokenLive || !definition?.publicMintEnabled || !meta?.catalogSealed || definition.minted >= definition.cap || !account || wrongChain || busy}>{!paymentTokenLive ? "等待 TINYAI 上线" : definition && definition.minted >= definition.cap ? "售罄" : "Mint 1 个"}</button></div>
        </article>;
      })}</div>
    </section>

    <footer><span>TINYAI LIFE PROTOCOL</span><span>{meta?.versionLabel || config.buildLabel}</span><span>MINT ONLY / FUSE IN MY AI</span></footer>
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
