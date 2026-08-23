"use client";

import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  decodeEventLog,
  defineChain,
  encodeFunctionData,
  formatUnits,
  http,
  parseSignature,
  toHex,
  type Address,
  type Hash,
} from "viem";
import { chatAbi, intentNames, modelCardAbi, tokenAbi, type DeploymentConfig } from "@/lib/contracts";

type Stage = "idle" | "connecting" | "previewing" | "signing" | "approving" | "submitted" | "confirming" | "confirmed" | "failed";
type PaymentMode = "permit" | "approve";
type Inference = {
  response: string;
  intent: number;
  secondaryIntent: number;
  sentiment: number;
  nextMood: number;
  confidence: number;
  variant: number;
  nextContext: Hash;
  chinese: boolean;
  followedContext: boolean;
};
type ModelMeta = {
  version: number;
  fee: bigint;
  burnBps: number;
  treasury: Address;
  token: Address;
  tokenName: string;
  tokenSymbol: string;
  decimals: number;
  totalChats: bigint;
  modelCard: Address;
  modelBytes: bigint;
  activeFeatures: number;
  weightCount: number;
  firstWeightHash: Hash;
  zhHash: Hash;
  enHash: Hash;
  corpusHash: Hash;
  integrity: boolean;
};
type WalletMeta = { balance: bigint; allowance: bigint; turns: number; mood: number; lastIntent: number };
type Message = { id: string; role: "user" | "ai"; text: string; intent?: number; secondaryIntent?: number; confidence?: number; followedContext?: boolean; mode?: "preview" | "confirmed" };
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;
const prompts = ["你为什么算真正的链上 AI？", "怎么保护我的钱包？", "解释一下 Gas 费用", "给我一个链上产品点子"];
const stageCopy: Record<Stage, string> = {
  idle: "等待输入", connecting: "连接钱包…", previewing: "EVM 正在推理…", signing: "等待钱包签名…",
  approving: "授权代币…", submitted: "交易已提交", confirming: "等待区块确认…", confirmed: "回答已永久上链", failed: "操作失败",
};

function short(value?: string | null, left = 6, right = 4) {
  if (!value) return "未读取";
  return value.length <= left + right + 1 ? value : `${value.slice(0, left)}…${value.slice(-right)}`;
}

function explainError(error: unknown) {
  const value = error as { shortMessage?: string; message?: string; code?: number };
  if (value?.code === 4001) return "你在钱包里取消了操作。";
  const message = value?.shortMessage || value?.message || "未知错误";
  if (/insufficient funds/i.test(message)) return "原生币不足，无法支付 Gas。";
  if (/allowance|transfer amount exceeds/i.test(message)) return "代币余额或授权不足。";
  if (/chain|network/i.test(message)) return "钱包网络不匹配，请切换到目标链。";
  return message.split("\n")[0].slice(0, 240);
}

export function ChatConsole({ config }: { config: DeploymentConfig }) {
  const chain = useMemo(() => defineChain({
    id: config.chainId,
    name: config.chainName,
    nativeCurrency: { name: config.nativeSymbol, symbol: config.nativeSymbol, decimals: 18 },
    rpcUrls: { default: { http: ["/api/rpc"] } },
    blockExplorers: config.explorerBaseUrl ? { default: { name: "Explorer", url: config.explorerBaseUrl } } : undefined,
  }), [config]);
  const publicClient = useMemo(() => createPublicClient({ chain, transport: http("/api/rpc", { batch: { batchSize: 10, wait: 5 } }) }), [chain]);

  const [account, setAccount] = useState<Address | null>(null);
  const [walletChain, setWalletChain] = useState<number | null>(null);
  const [meta, setMeta] = useState<ModelMeta | null>(null);
  const [walletMeta, setWalletMeta] = useState<WalletMeta | null>(null);
  const [prompt, setPrompt] = useState("你为什么算真正的链上 AI？");
  const [messages, setMessages] = useState<Message[]>([]);
  const [stage, setStage] = useState<Stage>("idle");
  const [paymentMode, setPaymentMode] = useState<PaymentMode>("permit");
  const [error, setError] = useState<string | null>(null);
  const [lastTx, setLastTx] = useState<Hash | null>(null);
  const [gasEstimate, setGasEstimate] = useState<bigint | null>(null);
  const [loadingMeta, setLoadingMeta] = useState(Boolean(config.chatAddress));
  const walletReadVersion = useRef(0);

  const deployed = Boolean(config.chatAddress);
  const wrongChain = account !== null && walletChain !== null && walletChain !== config.chainId;
  const promptBytes = new TextEncoder().encode(prompt).length;
  const busy = !["idle", "confirmed", "failed"].includes(stage);
  const paidChat = Boolean(meta && meta.fee > 0n && meta.token !== ZERO_ADDRESS);
  const modelReady = Boolean(meta?.integrity);
  const walletStateReady = !paidChat || walletMeta !== null;
  const insufficientToken = Boolean(paidChat && meta && walletMeta && walletMeta.balance < meta.fee);

  const loadWalletMeta = useCallback(async (user: Address, currentMeta: ModelMeta) => {
    if (!config.chatAddress) return;
    const requestVersion = ++walletReadVersion.current;
    try {
      const memory = await publicClient.readContract({ address: config.chatAddress, abi: chatAbi, functionName: "memoryOf", args: [user] });
      const [balance, allowance] = currentMeta.fee === 0n || currentMeta.token === ZERO_ADDRESS ? [0n, 0n] : await Promise.all([
        publicClient.readContract({ address: currentMeta.token, abi: tokenAbi, functionName: "balanceOf", args: [user] }),
        publicClient.readContract({ address: currentMeta.token, abi: tokenAbi, functionName: "allowance", args: [user, config.chatAddress] }),
      ]);
      if (requestVersion !== walletReadVersion.current) return;
      setWalletMeta({ balance, allowance, turns: memory.turns, mood: memory.mood, lastIntent: memory.lastIntent });
    } catch (cause) {
      if (requestVersion !== walletReadVersion.current) return;
      setWalletMeta(null);
      setError(`读取钱包链上状态失败：${explainError(cause)}`);
    }
  }, [config.chatAddress, publicClient]);

  const loadMeta = useCallback(async () => {
    if (!config.chatAddress) return null;
    setLoadingMeta(true);
    setMeta(null);
    try {
      const [version, fee, burnBps, treasury, token, modelCard, totalChats] = await Promise.all([
        publicClient.readContract({ address: config.chatAddress, abi: chatAbi, functionName: "VERSION" }),
        publicClient.readContract({ address: config.chatAddress, abi: chatAbi, functionName: "feePerChat" }),
        publicClient.readContract({ address: config.chatAddress, abi: chatAbi, functionName: "burnBps" }),
        publicClient.readContract({ address: config.chatAddress, abi: chatAbi, functionName: "treasury" }),
        publicClient.readContract({ address: config.chatAddress, abi: chatAbi, functionName: "paymentToken" }),
        publicClient.readContract({ address: config.chatAddress, abi: chatAbi, functionName: "modelCard" }),
        publicClient.readContract({ address: config.chatAddress, abi: chatAbi, functionName: "totalChats" }),
      ]);
      const [chunkCount, modelBytes, activeFeatures] = await Promise.all([
        publicClient.readContract({ address: modelCard, abi: modelCardAbi, functionName: "MODEL_CHUNK_COUNT" }),
        publicClient.readContract({ address: modelCard, abi: modelCardAbi, functionName: "MODEL_BYTES" }),
        publicClient.readContract({ address: modelCard, abi: modelCardAbi, functionName: "ACTIVE_FEATURES" }),
      ]);
      const [firstWeightHash, zhHash, enHash, corpusHash, integrity] = await Promise.all([
        publicClient.readContract({ address: modelCard, abi: modelCardAbi, functionName: "weightsCodeHashes", args: [0n] }),
        publicClient.readContract({ address: modelCard, abi: modelCardAbi, functionName: "zhLexiconCodeHash" }),
        publicClient.readContract({ address: modelCard, abi: modelCardAbi, functionName: "enLexiconCodeHash" }),
        publicClient.readContract({ address: modelCard, abi: modelCardAbi, functionName: "corpusSha256" }),
        publicClient.readContract({ address: modelCard, abi: modelCardAbi, functionName: "integrityOk" }),
      ]);
      const [tokenName, tokenSymbol, decimals] = fee === 0n || token === ZERO_ADDRESS ? ["Free Chat", "FREE", 18] as const : await Promise.all([
        publicClient.readContract({ address: token, abi: tokenAbi, functionName: "name" }),
        publicClient.readContract({ address: token, abi: tokenAbi, functionName: "symbol" }),
        publicClient.readContract({ address: token, abi: tokenAbi, functionName: "decimals" }),
      ]);
      const next: ModelMeta = { version, fee, burnBps, treasury, token, tokenName, tokenSymbol, decimals, totalChats, modelCard, modelBytes, activeFeatures, weightCount: Number(chunkCount), firstWeightHash, zhHash, enHash, corpusHash, integrity };
      setMeta(next);
      return next;
    } catch (cause) {
      setError(`读取链上模型失败：${explainError(cause)}`);
      return null;
    } finally { setLoadingMeta(false); }
  }, [config.chatAddress, publicClient]);

  useEffect(() => {
    const task = window.setTimeout(() => { void loadMeta(); }, 0);
    return () => window.clearTimeout(task);
  }, [loadMeta]);

  useEffect(() => {
    const provider = window.ethereum;
    if (!provider) return;
    let cancelled = false;
    const invalidateWalletReads = () => {
      walletReadVersion.current += 1;
      setWalletMeta(null);
      setLastTx(null);
    };
    const accountsChanged = (...args: unknown[]) => {
      const accounts = args[0] as string[];
      invalidateWalletReads();
      setAccount(accounts?.[0] as Address || null);
    };
    const chainChanged = (...args: unknown[]) => {
      invalidateWalletReads();
      setWalletChain(Number(BigInt(args[0] as string)));
    };
    const disconnected = () => {
      invalidateWalletReads();
      setAccount(null);
      setWalletChain(null);
    };
    provider.on?.("accountsChanged", accountsChanged);
    provider.on?.("chainChanged", chainChanged);
    provider.on?.("disconnect", disconnected);
    void Promise.all([
      provider.request({ method: "eth_accounts" }) as Promise<string[]>,
      provider.request({ method: "eth_chainId" }) as Promise<string>,
    ]).then(([accounts, chainId]) => {
      if (cancelled) return;
      invalidateWalletReads();
      setAccount(accounts?.[0] as Address || null);
      setWalletChain(Number(BigInt(chainId)));
    }).catch(() => { /* Silent discovery must never block read-only mode. */ });
    return () => {
      cancelled = true;
      provider.removeListener?.("accountsChanged", accountsChanged);
      provider.removeListener?.("chainChanged", chainChanged);
      provider.removeListener?.("disconnect", disconnected);
    };
  }, []);

  useEffect(() => {
    if (!account || !meta || walletChain !== config.chainId) return;
    const task = window.setTimeout(() => { void loadWalletMeta(account, meta); }, 0);
    return () => window.clearTimeout(task);
  }, [account, config.chainId, meta, walletChain, loadWalletMeta]);

  async function connectWallet() {
    setError(null);
    if (!window.ethereum) { setError("没有检测到浏览器钱包扩展。你仍然可以使用免费链上预览。 "); return; }
    setStage("connecting");
    try {
      const client = createWalletClient({ chain, transport: custom(window.ethereum) });
      const [selected] = await client.requestAddresses();
      setWalletMeta(null);
      setLastTx(null);
      setAccount(selected);
      setWalletChain(await client.getChainId());
      setError(null);
      setStage("idle");
    } catch (cause) { setError(explainError(cause)); setStage("failed"); }
  }

  async function switchNetwork() {
    if (!window.ethereum) return;
    setError(null);
    try {
      await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: toHex(config.chainId) }] });
      setWalletChain(config.chainId);
      setError(null);
    } catch (cause) { setError(`钱包没有自动切链：${explainError(cause)} 请手动添加或选择 ${config.chainName}。`); }
  }

  function validatePrompt() {
    if (!deployed) throw new Error("当前只是未部署构建，先完成本地或主网部署。 ");
    if (!prompt.trim()) throw new Error("请输入问题。 ");
    if (promptBytes > 280) throw new Error("问题超过 280 字节；中文通常最多约 93 个字。 ");
  }

  async function preview(event?: FormEvent) {
    event?.preventDefault();
    setError(null);
    try {
      validatePrompt();
      if (!config.chatAddress) return;
      setStage("previewing");
      const user = account || ZERO_ADDRESS;
      const callData = encodeFunctionData({ abi: chatAbi, functionName: "preview", args: [user, prompt] });
      const [result, estimated] = await Promise.all([
        publicClient.readContract({ address: config.chatAddress, abi: chatAbi, functionName: "preview", args: [user, prompt] }),
        publicClient.estimateGas({ to: config.chatAddress, data: callData, account: user }),
      ]);
      const output = result as Inference;
      setGasEstimate(estimated);
      setMessages((current) => [...current,
        { id: crypto.randomUUID(), role: "user", text: prompt, mode: "preview" },
        { id: crypto.randomUUID(), role: "ai", text: output.response, intent: output.intent, secondaryIntent: output.secondaryIntent, confidence: output.confidence, followedContext: output.followedContext, mode: "preview" },
      ]);
      setStage("idle");
    } catch (cause) { setError(explainError(cause)); setStage("failed"); }
  }

  async function writeChat() {
    setError(null);
    try {
      validatePrompt();
      if (!account || !window.ethereum) throw new Error("请先连接钱包。 ");
      if (wrongChain) throw new Error(`请先切换到 ${config.chainName}。`);
      if (!config.chatAddress) return;
      const currentMeta = meta || await loadMeta();
      if (!currentMeta) throw new Error("链上配置尚未读取完成。 ");
      if (!currentMeta.integrity) throw new Error("链上模型完整性检查未通过，已阻止交易。 ");
      const client = createWalletClient({ account, chain, transport: custom(window.ethereum) });
      let txHash: Hash;

      if (currentMeta.fee > 0n && (walletMeta?.allowance || 0n) < currentMeta.fee && paymentMode === "permit") {
        setStage("signing");
        const nonce = await publicClient.readContract({ address: currentMeta.token, abi: tokenAbi, functionName: "nonces", args: [account] });
        const deadline = BigInt(Math.floor(Date.now() / 1_000) + 20 * 60);
        const signature = await client.signTypedData({
          account,
          domain: { name: currentMeta.tokenName, version: "1", chainId: config.chainId, verifyingContract: currentMeta.token },
          types: { Permit: [
            { name: "owner", type: "address" }, { name: "spender", type: "address" },
            { name: "value", type: "uint256" }, { name: "nonce", type: "uint256" }, { name: "deadline", type: "uint256" },
          ] },
          primaryType: "Permit",
          message: { owner: account, spender: config.chatAddress, value: currentMeta.fee, nonce, deadline },
        });
        const parsed = parseSignature(signature);
        const v = Number(parsed.v ?? BigInt((parsed.yParity ?? 0) + 27));
        const simulation = await publicClient.simulateContract({ account, address: config.chatAddress, abi: chatAbi, functionName: "chatWithPermit", args: [prompt, deadline, v, parsed.r, parsed.s] });
        setStage("signing");
        txHash = await client.writeContract(simulation.request);
      } else {
        if (currentMeta.fee > 0n && (walletMeta?.allowance || 0n) < currentMeta.fee) {
          const approvalSimulation = await publicClient.simulateContract({ account, address: currentMeta.token, abi: tokenAbi, functionName: "approve", args: [config.chatAddress, currentMeta.fee] });
          setStage("approving");
          const approvalHash = await client.writeContract(approvalSimulation.request);
          setLastTx(approvalHash);
          setStage("confirming");
          const approvalReceipt = await publicClient.waitForTransactionReceipt({
            hash: approvalHash,
            onReplaced: ({ transaction }) => setLastTx(transaction.hash),
          });
          if (approvalReceipt.status !== "success") throw new Error("代币授权交易失败。 ");
        }
        const simulation = await publicClient.simulateContract({ account, address: config.chatAddress, abi: chatAbi, functionName: "chat", args: [prompt] });
        setStage("signing");
        txHash = await client.writeContract(simulation.request);
      }

      setStage("submitted");
      setLastTx(txHash);
      setStage("confirming");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: txHash,
        confirmations: 1,
        onReplaced: ({ transaction }) => setLastTx(transaction.hash),
      });
      if (receipt.status !== "success") throw new Error("聊天交易执行失败。 ");
      let answer: { response: string; intent: number; secondaryIntent: number; confidence: number; followedContext: boolean } | null = null;
      for (const log of receipt.logs) {
        try {
          const decoded = decodeEventLog({ abi: chatAbi, data: log.data, topics: log.topics });
          if (decoded.eventName === "Chat") answer = { response: decoded.args.response, intent: decoded.args.intent, secondaryIntent: decoded.args.secondaryIntent, confidence: decoded.args.confidence, followedContext: decoded.args.followedContext };
        } catch { /* Other contract logs are expected. */ }
      }
      if (!answer) throw new Error("交易成功，但没有找到 Chat 事件。 ");
      setMessages((current) => [...current,
        { id: crypto.randomUUID(), role: "user", text: prompt, mode: "confirmed" },
        { id: crypto.randomUUID(), role: "ai", text: answer.response, intent: answer.intent, secondaryIntent: answer.secondaryIntent, confidence: answer.confidence, followedContext: answer.followedContext, mode: "confirmed" },
      ]);
      setStage("confirmed");
      const refreshed = await loadMeta();
      if (refreshed) await loadWalletMeta(account, refreshed);
    } catch (cause) { setError(explainError(cause)); setStage("failed"); }
  }

  const feeLabel = meta ? paidChat ? `${formatUnits(meta.fee, meta.decimals)} ${meta.tokenSymbol}` : "免费（仅 Gas）" : "读取中";
  const gasLabel = gasEstimate ? `${Number(gasEstimate).toLocaleString()} gas` : "提交问题后估算";

  return (
    <main className="shell">
      <div className="noise" aria-hidden="true" />
      <header className="topbar">
        <a className="brand" href="#top" aria-label="TinyAI 首页"><span className="brand-mark">T</span><span>TINY<span>AI</span></span></a>
        <div className="network"><i className={deployed ? "pulse" : "pulse muted"} />{config.chainName}<small>{config.buildLabel}</small></div>
        <button className="wallet-button" type="button" onClick={connectWallet} disabled={stage === "connecting"}>{account ? short(account) : "连接钱包"}</button>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">EVM NATIVE INTELLIGENCE / VERSION 03</p>
          <h1>不是把答案<br />写上链。<em>是在链上想。</em></h1>
          <p className="lede">514,254 字节稀疏量化模型，13,531 个公开语义特征，27 类意图与情绪判断，能承接上一轮主题。没有推理服务器，没有管理员后门。</p>
        </div>
        <div className="truth-stamp"><strong>{meta?.integrity ? "VERIFIED" : deployed ? "CHECKING" : "LOCAL"}</strong><span>WEIGHTS · INFERENCE · MEMORY</span><b>100% EVM</b></div>
      </section>

      <section className="workspace">
        <div className="terminal">
          <div className="terminal-head"><span><i /> ONCHAIN TERMINAL</span><span className="stage" aria-live="polite">{stageCopy[stage]}</span></div>
          <div className="messages" aria-live="polite">
            {messages.length === 0 ? <div className="empty-state"><span>01</span><h2>问它一个问题</h2><p>“预览”会在 RPC 节点里执行同一份 EVM 字节码，不花 Gas；“写入链上”{paidChat ? "会支付固定代币费用，" : "只需支付网络 Gas，"}并永久保存记忆与公开事件。</p></div> : messages.map((message) => (
              <article className={`message ${message.role}`} key={message.id}>
                <div className="message-label">{message.role === "user" ? "YOU" : "TINYAI"}<span>{message.mode === "confirmed" ? "已确认" : "只读预览"}</span></div>
                <p>{message.text}</p>
                {message.role === "ai" && <div className="message-meta">意图 / {intentNames[message.intent ?? 26]}{message.secondaryIntent !== undefined && message.secondaryIntent !== 255 ? ` + ${intentNames[message.secondaryIntent]}` : ""}　分类余量 / {((message.confidence ?? 0) / 100).toFixed(0)}%{message.followedContext ? "　承接上轮" : ""}</div>}
              </article>
            ))}
          </div>
          <form className="composer" onSubmit={preview}>
            <textarea aria-label="聊天问题" value={prompt} onChange={(event) => setPrompt(event.target.value)} placeholder="输入中文或英文问题…" maxLength={280} disabled={busy} />
            <div className="composer-foot"><span className={promptBytes > 280 ? "over" : ""}>{promptBytes} / 280 bytes</span><button className="preview-button" type="submit" disabled={busy || !deployed || loadingMeta || !modelReady}>免费链上预览 <b>↗</b></button></div>
          </form>
          {error && <div className="error" role="alert"><b>!</b><span>{error}</span></div>}
          <div className="quick-prompts">{prompts.map((value) => <button type="button" key={value} onClick={() => setPrompt(value)}>{value}</button>)}</div>
        </div>

        <aside className="control-panel">
          <div className="panel-title"><span>WRITE MODE</span><b>02</b></div>
          {!deployed ? <div className="undeployed"><strong>尚未部署</strong><p>界面与合约已就绪。主网地址只会在用户确认部署交易后写入。</p></div> : loadingMeta ? <div className="skeleton">正在读取链上配置…</div> : !meta ? <div className="read-error"><strong>链上配置暂不可用</strong><p>没有使用缓存值冒充实时状态。请检查 RPC 后重新读取。</p><button type="button" onClick={() => { void loadMeta(); }}>重新读取</button></div> : <>
            {!meta.integrity && <div className="integrity-error" role="alert">模型完整性未通过，预览和交易均已停用。</div>}
            {wrongChain && <button className="switch-button" type="button" onClick={switchNetwork}>切换到 {config.chainName}</button>}
            <dl className="payment-grid">
              <div><dt>聊天费</dt><dd>{feeLabel}</dd></div><div><dt>黑洞份额</dt><dd>{meta ? `${meta.burnBps / 100}%` : "未读取"}</dd></div>
              <div><dt>钱包余额</dt><dd>{paidChat ? walletMeta && meta ? `${Number(formatUnits(walletMeta.balance, meta.decimals)).toLocaleString()} ${meta.tokenSymbol}` : "连接后读取" : "无需代币"}</dd></div>
              <div><dt>记忆轮次</dt><dd>{walletMeta ? walletMeta.turns : "未读取"}</dd></div>
            </dl>
            {paidChat ? <div className="mode-toggle" role="group" aria-label="支付模式"><button type="button" aria-pressed={paymentMode === "permit"} className={paymentMode === "permit" ? "active" : ""} onClick={() => setPaymentMode("permit")}>Permit 一次交易</button><button type="button" aria-pressed={paymentMode === "approve"} className={paymentMode === "approve" ? "active" : ""} onClick={() => setPaymentMode("approve")}>Approve 兼容模式</button></div> : <div className="mode-toggle" aria-label="免费实验模式"><button type="button" className="active" disabled>免费实验核心</button><button type="button" disabled>代币稍后接入</button></div>}
            <button className="write-button" type="button" onClick={writeChat} disabled={busy || wrongChain || !account || !meta.integrity || !walletStateReady || insufficientToken}><span>{!account ? "先连接钱包" : wrongChain ? `先切换到 ${config.chainName}` : paidChat && !walletMeta ? "正在读取余额" : insufficientToken ? `${meta.tokenSymbol} 余额不足` : paidChat ? "支付并写入链上" : "支付 Gas 并写入"}</span><b>→</b></button>
            <p className="payment-note">{paidChat ? "Permit 只签署本次固定费用授权；兼容模式最多产生授权 + 聊天两笔交易，不会请求无限授权。黑洞份额转入 0x…dEaD，totalSupply 不会减少。" : "当前核心不收代币，只需钱包支付网络 Gas；以后可复用同一模型卡部署固定代币收费版。"}</p>
          </>}
          <div className="cost-strip"><span>最近推理估算</span><strong>{gasLabel}</strong></div>
          {lastTx && <a className="tx-link" href={config.explorerBaseUrl ? `${config.explorerBaseUrl}/tx/${lastTx}` : "#"} target="_blank" rel="noreferrer">查看交易 {short(lastTx, 10, 6)} ↗</a>}
        </aside>
      </section>

      <section className="evidence">
        <div className="evidence-intro"><p className="eyebrow">DON&apos;T TRUST. VERIFY.</p><h2>所谓“真链上”，<br />每一层都要能指出地址。</h2><p>前端可以消失，模型仍能被任何 RPC、区块浏览器或其他合约调用。训练发生在链下，这是事实边界；推理与最终回答发生在链上。</p></div>
        <div className="evidence-table">
          <EvidenceRow index="A" label="CHAT ENGINE" value={config.chatAddress} state={deployed ? "CODE" : "PENDING"} explorer={config.explorerBaseUrl} />
          <EvidenceRow index="B" label="MODEL CARD" value={meta?.modelCard} state={meta?.integrity ? "LOCKED" : "未读取"} explorer={config.explorerBaseUrl} />
          <EvidenceRow index="C" label="INT8 MODEL" value={meta?.firstWeightHash} state={meta ? `${meta.modelBytes.toLocaleString()} B / ${meta.weightCount} BLOBS` : "514,254 B / 22 BLOBS"} />
          <EvidenceRow index="D" label="ZH / EN LEXICON" value={meta ? `${short(meta.zhHash, 12, 8)} · ${short(meta.enHash, 12, 8)}` : null} state="216 REPLIES" />
          <EvidenceRow index="E" label="CORPUS SHA-256" value={meta?.corpusHash} state="REPRODUCIBLE" />
        </div>
      </section>

      <section className="limits">
        <div><span>01</span><h3>它不是大模型</h3><p>这是有限语义词典、量化意图与情绪头加不可变回答库。陌生措辞独立验收 top-1 为 87.65%，但仍不能假装拥有 ChatGPT 的开放推理能力。</p></div>
        <div><span>02</span><h3>聊天完全公开</h3><p>问题、回答、钱包地址和记忆摘要都可永久查询。不要输入姓名、密码、私钥或任何隐私。</p></div>
        <div><span>03</span><h3>状态不可偷偷升级</h3><p>当前版本没有管理员、代理或模型替换入口。升级只能部署新版本，由用户明确选择迁移。</p></div>
      </section>

      <footer><span>TINYAI / ONCHAIN BY CONSTRUCTION</span><span>{meta ? `${meta.totalChats.toString()} CONFIRMED CHATS` : "RESEARCH BUILD"}</span><span>MODEL V{meta?.version ?? 3}</span></footer>
    </main>
  );
}

function EvidenceRow({ index, label, value, state, explorer }: { index: string; label: string; value?: string | null; state: string; explorer?: string }) {
  const rendered = value || "等待部署地址";
  const isAddress = /^0x[0-9a-fA-F]{40}$/.test(rendered);
  return <div className="evidence-row"><b>{index}</b><span>{label}</span>{isAddress && explorer ? <a href={`${explorer}/address/${rendered}`} target="_blank" rel="noreferrer">{short(rendered, 12, 8)} ↗</a> : <code title={rendered}>{short(rendered, 14, 10)}</code>}<em>{state}</em></div>;
}
