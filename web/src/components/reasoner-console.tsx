"use client";

import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  decodeEventLog,
  defineChain,
  encodeFunctionData,
  http,
  toHex,
  type Address,
  type Hash,
} from "viem";
import { reasonerV4Abi, type DeploymentConfig } from "@/lib/contracts";

type Stage = "idle" | "connecting" | "previewing" | "signing" | "submitted" | "confirming" | "confirmed" | "failed";
type Depth = 0 | 1;
type ReasoningResult = {
  response: string;
  domain: number;
  queryType: number;
  confidence: number;
  depth: number;
  stepCount: number;
  facts: bigint;
  conclusions: bigint;
  traceHash: Hash;
  nextContext: Hash;
  chinese: boolean;
  followedContext: boolean;
  trace: readonly Hash[];
};
type ReasonerMeta = {
  version: number;
  ruleCount: number;
  maxTraceSteps: number;
  knowledge: Address;
  knowledgeHash: Hash;
  knowledgeCodeHash: Hash;
  integrity: boolean;
  totalChats: bigint;
  architecture: string;
  truthBoundary: string;
};
type WalletMemory = { turns: number; lastDomain: number; lastQuery: number; confidence: number };
type Message = {
  id: string;
  role: "user" | "ai";
  text: string;
  mode: "preview" | "confirmed";
  reasoning?: ReasoningResult;
};
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;
const MASK_64 = (1n << 64n) - 1n;
const SPECULATIVE_ANSWER = 1n << 13n;
const domainNames = ["未知", "身份", "链上 AI", "人类", "BSC", "区块链", "Gas", "钱包", "代币", "合约安全"];
const queryNames = ["未识别", "问候", "定义", "为什么", "怎么做", "比较", "风险", "追问"];
const opcodeNames: Record<number, string> = { 1: "解析问题", 2: "装载事实", 3: "应用规则", 4: "验证结论", 5: "生成回答" };
const ruleNames = [
  "BSC → EVM", "BSC → BNB Gas", "EVM → 智能合约", "确认 BSC 兼容 EVM", "确认 BSC 使用 BNB",
  "确认 BSC 可编程", "人类 → 生物属性", "人类 → 社会属性", "合并成人类结论", "计算预算依赖算法",
  "Gas 扩容不等于智力", "AI 能力有边界", "验证纯链上执行", "增发 + 管理员风险", "代理 + 管理员风险",
  "保护私钥", "核对签名", "低置信度 → 通用生成",
];
const factNames: Array<[bigint, string]> = [
  [1n << 0n, "AI"], [1n << 1n, "人类"], [1n << 2n, "BSC"], [1n << 3n, "区块链"],
  [1n << 4n, "Gas"], [1n << 5n, "钱包"], [1n << 6n, "代币"], [1n << 7n, "合约"],
  [1n << 8n, "EVM"], [1n << 9n, "BNB Gas"], [1n << 10n, "智能合约"], [1n << 11n, "计算预算"],
  [1n << 12n, "规模变化"], [1n << 13n, "取决于算法"], [1n << 14n, "链上执行"],
  [1n << 15n, "模型不可变"], [1n << 16n, "无推理服务器"], [1n << 17n, "确定性"],
  [1n << 18n, "生物属性"], [1n << 19n, "社会属性"], [1n << 20n, "推理"],
  [1n << 21n, "私钥"], [1n << 22n, "签名"], [1n << 23n, "可增发"], [1n << 24n, "管理员"],
  [1n << 25n, "代理"], [1n << 26n, "黑名单"], [1n << 27n, "固定回答边界"],
  [1n << 28n, "链上知识"], [1n << 29n, "低置信度"], [1n << 30n, "开放问题"],
  [1n << 31n, "提示条件化"],
];
const conclusionNames: Array<[bigint, string]> = [
  [1n << 0n, "BSC 兼容 EVM"], [1n << 1n, "BSC 使用 BNB"], [1n << 2n, "BSC 可编程"],
  [1n << 3n, "人类是生物与社会存在"], [1n << 4n, "Gas 不等于智力"], [1n << 5n, "架构决定收益"],
  [1n << 6n, "推理可在链上复核"], [1n << 7n, "存在供应风险"], [1n << 8n, "存在升级风险"],
  [1n << 9n, "保护私钥"], [1n << 10n, "核对签名"], [1n << 12n, "AI 能力有边界"],
  [SPECULATIVE_ANSWER, "低置信度通用生成"],
];
const prompts = [
  "如果把 Gas 提高十倍，AI 会聪明十倍吗？",
  "恐龙为什么灭绝？",
  "怎么做红烧肉？",
  "比较木星和一杯咖啡",
  "量子香蕉今晚做梦吗？",
];
const stageCopy: Record<Stage, string> = {
  idle: "等待输入", connecting: "连接钱包…", previewing: "EVM 正在逐步推导…", signing: "等待钱包签名…",
  submitted: "交易已提交", confirming: "等待区块确认…", confirmed: "推理与轨迹已永久上链", failed: "操作失败",
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
  if (/chain|network/i.test(message)) return "钱包网络不匹配，请切换到目标链。";
  return message.split("\n")[0].slice(0, 240);
}

function namesFor(bits: bigint, catalog: Array<[bigint, string]>) {
  return catalog.filter(([flag]) => (bits & flag) !== 0n).map(([, name]) => name);
}

function decodeTrace(result: ReasoningResult) {
  let priorFacts = 0n;
  let priorConclusions = 0n;
  return result.trace.slice(0, result.stepCount).map((word, index) => {
    const packed = BigInt(word);
    const opcode = Number((packed >> 248n) & 0xffn);
    const ruleId = Number((packed >> 240n) & 0xffn);
    const facts = (packed >> 144n) & MASK_64;
    const conclusions = (packed >> 80n) & MASK_64;
    const addedFacts = namesFor(facts & ~priorFacts, factNames);
    const addedConclusions = namesFor(conclusions & ~priorConclusions, conclusionNames);
    priorFacts = facts;
    priorConclusions = conclusions;
    return {
      index: index + 1,
      opcode,
      ruleId,
      title: opcode === 3 ? ruleNames[ruleId] || `规则 ${ruleId}` : opcodeNames[opcode] || `步骤 ${opcode}`,
      addedFacts,
      addedConclusions,
      word,
    };
  });
}

export function ReasonerConsole({ config }: { config: DeploymentConfig }) {
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
  const [meta, setMeta] = useState<ReasonerMeta | null>(null);
  const [walletMemory, setWalletMemory] = useState<WalletMemory | null>(null);
  const [prompt, setPrompt] = useState(prompts[0]);
  const [depth, setDepth] = useState<Depth>(1);
  const [messages, setMessages] = useState<Message[]>([]);
  const [stage, setStage] = useState<Stage>("idle");
  const [error, setError] = useState<string | null>(null);
  const [lastTx, setLastTx] = useState<Hash | null>(null);
  const [gasEstimate, setGasEstimate] = useState<bigint | null>(null);
  const [loadingMeta, setLoadingMeta] = useState(Boolean(config.chatAddress));
  const walletReadVersion = useRef(0);

  const deployed = Boolean(config.chatAddress);
  const wrongChain = account !== null && walletChain !== null && walletChain !== config.chainId;
  const promptBytes = new TextEncoder().encode(prompt).length;
  const busy = !["idle", "confirmed", "failed"].includes(stage);
  const modelReady = Boolean(meta?.integrity);

  const loadMemory = useCallback(async (user: Address) => {
    if (!config.chatAddress) return;
    const requestVersion = ++walletReadVersion.current;
    try {
      const memory = await publicClient.readContract({
        address: config.chatAddress, abi: reasonerV4Abi, functionName: "memoryOf", args: [user],
      });
      if (requestVersion !== walletReadVersion.current) return;
      setWalletMemory({
        turns: memory.turns,
        lastDomain: memory.lastDomain,
        lastQuery: memory.lastQuery,
        confidence: memory.confidence,
      });
    } catch (cause) {
      if (requestVersion !== walletReadVersion.current) return;
      setWalletMemory(null);
      setError(`读取钱包链上记忆失败：${explainError(cause)}`);
    }
  }, [config.chatAddress, publicClient]);

  const loadMeta = useCallback(async () => {
    if (!config.chatAddress) return null;
    setLoadingMeta(true);
    setMeta(null);
    try {
      const [version, ruleCount, maxTraceSteps, knowledge, knowledgeHash, knowledgeCodeHash, integrity, totalChats, architecture, truthBoundary] = await Promise.all([
        publicClient.readContract({ address: config.chatAddress, abi: reasonerV4Abi, functionName: "VERSION" }),
        publicClient.readContract({ address: config.chatAddress, abi: reasonerV4Abi, functionName: "RULE_COUNT" }),
        publicClient.readContract({ address: config.chatAddress, abi: reasonerV4Abi, functionName: "MAX_TRACE_STEPS" }),
        publicClient.readContract({ address: config.chatAddress, abi: reasonerV4Abi, functionName: "knowledge" }),
        publicClient.readContract({ address: config.chatAddress, abi: reasonerV4Abi, functionName: "KNOWLEDGE_HASH" }),
        publicClient.readContract({ address: config.chatAddress, abi: reasonerV4Abi, functionName: "knowledgeCodeHash" }),
        publicClient.readContract({ address: config.chatAddress, abi: reasonerV4Abi, functionName: "integrityOk" }),
        publicClient.readContract({ address: config.chatAddress, abi: reasonerV4Abi, functionName: "totalChats" }),
        publicClient.readContract({ address: config.chatAddress, abi: reasonerV4Abi, functionName: "architecture" }),
        publicClient.readContract({ address: config.chatAddress, abi: reasonerV4Abi, functionName: "truthBoundary" }),
      ]);
      const next = { version, ruleCount, maxTraceSteps, knowledge, knowledgeHash, knowledgeCodeHash, integrity, totalChats, architecture, truthBoundary };
      setMeta(next);
      return next;
    } catch (cause) {
      setError(`读取 v4 链上推理器失败：${explainError(cause)}`);
      return null;
    } finally {
      setLoadingMeta(false);
    }
  }, [config.chatAddress, publicClient]);

  useEffect(() => {
    const task = window.setTimeout(() => { void loadMeta(); }, 0);
    return () => window.clearTimeout(task);
  }, [loadMeta]);

  useEffect(() => {
    const provider = window.ethereum;
    if (!provider) return;
    let cancelled = false;
    const invalidate = () => { walletReadVersion.current += 1; setWalletMemory(null); setLastTx(null); };
    const accountsChanged = (...args: unknown[]) => { invalidate(); setAccount((args[0] as string[])?.[0] as Address || null); };
    const chainChanged = (...args: unknown[]) => { invalidate(); setWalletChain(Number(BigInt(args[0] as string))); };
    const disconnected = () => { invalidate(); setAccount(null); setWalletChain(null); };
    provider.on?.("accountsChanged", accountsChanged);
    provider.on?.("chainChanged", chainChanged);
    provider.on?.("disconnect", disconnected);
    void Promise.all([
      provider.request({ method: "eth_accounts" }) as Promise<string[]>,
      provider.request({ method: "eth_chainId" }) as Promise<string>,
    ]).then(([accounts, chainId]) => {
      if (cancelled) return;
      invalidate();
      setAccount(accounts?.[0] as Address || null);
      setWalletChain(Number(BigInt(chainId)));
    }).catch(() => { /* Read-only mode does not require wallet discovery. */ });
    return () => {
      cancelled = true;
      provider.removeListener?.("accountsChanged", accountsChanged);
      provider.removeListener?.("chainChanged", chainChanged);
      provider.removeListener?.("disconnect", disconnected);
    };
  }, []);

  useEffect(() => {
    if (!account || walletChain !== config.chainId) return;
    const task = window.setTimeout(() => { void loadMemory(account); }, 0);
    return () => window.clearTimeout(task);
  }, [account, config.chainId, loadMemory, walletChain]);

  async function connectWallet() {
    setError(null);
    if (!window.ethereum) { setError("没有检测到浏览器钱包扩展。你仍然可以免费执行只读链上推理。"); return; }
    setStage("connecting");
    try {
      const client = createWalletClient({ chain, transport: custom(window.ethereum) });
      const [selected] = await client.requestAddresses();
      setAccount(selected);
      setWalletChain(await client.getChainId());
      setStage("idle");
    } catch (cause) { setError(explainError(cause)); setStage("failed"); }
  }

  async function switchNetwork() {
    if (!window.ethereum) return;
    setError(null);
    try {
      await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: toHex(config.chainId) }] });
      setWalletChain(config.chainId);
    } catch (cause) { setError(`钱包没有自动切链：${explainError(cause)} 请手动选择 ${config.chainName}。`); }
  }

  function validatePrompt() {
    if (!deployed) throw new Error("v4 推理器尚未部署到当前网络。");
    if (!prompt.trim()) throw new Error("请输入问题。");
    if (promptBytes > 280) throw new Error("问题超过 280 字节；中文通常最多约 93 个字。");
  }

  async function preview(event?: FormEvent) {
    event?.preventDefault();
    setError(null);
    try {
      validatePrompt();
      if (!config.chatAddress) return;
      setStage("previewing");
      const user = account || ZERO_ADDRESS;
      const callData = encodeFunctionData({ abi: reasonerV4Abi, functionName: "preview", args: [user, prompt, depth] });
      const [result, estimated] = await Promise.all([
        publicClient.readContract({ address: config.chatAddress, abi: reasonerV4Abi, functionName: "preview", args: [user, prompt, depth] }),
        publicClient.estimateGas({ to: config.chatAddress, data: callData, account: user }),
      ]);
      const output = result as ReasoningResult;
      setGasEstimate(estimated);
      setMessages((current) => [...current,
        { id: crypto.randomUUID(), role: "user", text: prompt, mode: "preview" },
        { id: crypto.randomUUID(), role: "ai", text: output.response, mode: "preview", reasoning: output },
      ]);
      setStage("idle");
    } catch (cause) { setError(explainError(cause)); setStage("failed"); }
  }

  async function writeChat() {
    setError(null);
    try {
      validatePrompt();
      if (!account || !window.ethereum) throw new Error("请先连接钱包。");
      if (wrongChain) throw new Error(`请先切换到 ${config.chainName}。`);
      if (!config.chatAddress) return;
      const currentMeta = meta || await loadMeta();
      if (!currentMeta?.integrity) throw new Error("链上模块完整性检查未通过，已阻止交易。");
      const client = createWalletClient({ account, chain, transport: custom(window.ethereum) });
      const simulation = await publicClient.simulateContract({
        account, address: config.chatAddress, abi: reasonerV4Abi, functionName: "chat", args: [prompt, depth],
      });
      setStage("signing");
      const txHash = await client.writeContract(simulation.request);
      setStage("submitted");
      setLastTx(txHash);
      setStage("confirming");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: txHash,
        confirmations: 1,
        onReplaced: ({ transaction }) => setLastTx(transaction.hash),
      });
      if (receipt.status !== "success") throw new Error("链上推理交易执行失败。");
      let answer: ReasoningResult | null = null;
      for (const log of receipt.logs) {
        try {
          const decoded = decodeEventLog({ abi: reasonerV4Abi, data: log.data, topics: log.topics });
          if (decoded.eventName !== "ReasonedChat") continue;
          answer = {
            response: decoded.args.response,
            domain: decoded.args.domain,
            queryType: decoded.args.queryType,
            confidence: decoded.args.confidence,
            depth: decoded.args.depth,
            stepCount: decoded.args.stepCount,
            facts: decoded.args.facts,
            conclusions: decoded.args.conclusions,
            traceHash: decoded.args.traceHash,
            nextContext: decoded.args.contextHash,
            chinese: /[\u3400-\u9fff]/u.test(prompt),
            followedContext: decoded.args.followedContext,
            trace: decoded.args.trace,
          };
        } catch { /* Ignore unrelated logs. */ }
      }
      if (!answer) throw new Error("交易成功，但没有找到 ReasonedChat 事件。");
      setMessages((current) => [...current,
        { id: crypto.randomUUID(), role: "user", text: prompt, mode: "confirmed" },
        { id: crypto.randomUUID(), role: "ai", text: answer.response, mode: "confirmed", reasoning: answer },
      ]);
      setStage("confirmed");
      await Promise.all([loadMeta(), loadMemory(account)]);
    } catch (cause) { setError(explainError(cause)); setStage("failed"); }
  }

  const gasLabel = gasEstimate ? `${Number(gasEstimate).toLocaleString()} gas` : "预览后显示";

  return (
    <main className="shell reasoner-shell">
      <div className="noise" aria-hidden="true" />
      <header className="topbar">
        <a className="brand" href="#top" aria-label="TinyAI 首页"><span className="brand-mark">T</span><span>TINY<span>AI</span></span></a>
        <div className="network"><i className={deployed ? "pulse" : "pulse muted"} />{config.chainName}<small>{config.buildLabel}</small></div>
        <button className="wallet-button" type="button" onClick={connectWallet} disabled={stage === "connecting"}>{account ? short(account) : "连接钱包"}</button>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">UNIVERSAL EVM ANSWERER / VERSION 04.1</p>
          <h1>不只回答题库。<br /><em>任何问题都能接住。</em></h1>
          <p className="lede">已知主题走事实和规则；陌生主题根据问题形式与原始提示在链上组合一个低置信度答案。每一步仍由 EVM 执行并留下可重放轨迹，但“总会回答”不等于“总是正确”。</p>
        </div>
        <div className="truth-stamp"><strong>{meta?.integrity ? "VERIFIED" : deployed ? "CHECKING" : "LOCAL"}</strong><span>FACTS · RULES · TRACE</span><b>PURE EVM</b></div>
      </section>

      <section className="workspace">
        <div className="terminal">
          <div className="terminal-head"><span><i /> REASONING TERMINAL</span><span className="stage" aria-live="polite">{stageCopy[stage]}</span></div>
          <div className="messages" aria-live="polite">
            {messages.length === 0 ? <div className="empty-state"><span>04.1</span><h2>随便问，不需要命中题库</h2><p>“只读运行”会让 RPC 节点完整执行推理器，不花你的 Gas。已知问题会给事实结论；未知问题也会回答，但会标成低置信度推测。</p></div> : messages.map((message) => (
              <article className={`message ${message.role}`} key={message.id}>
                <div className="message-label">{message.role === "user" ? "YOU" : "TINYAI V4.1"}<span>{message.reasoning && (message.reasoning.conclusions & SPECULATIVE_ANSWER) !== 0n ? `低置信度生成 · ${message.mode === "confirmed" ? "已确认" : "只读"}` : message.mode === "confirmed" ? "已确认" : "只读执行"}</span></div>
                <p>{message.text}</p>
                {message.reasoning && <ReasoningTrace result={message.reasoning} />}
              </article>
            ))}
          </div>
          <form className="composer" onSubmit={preview}>
            <textarea aria-label="聊天问题" value={prompt} onChange={(event) => setPrompt(event.target.value)} placeholder="输入任何中文或英文问题…" maxLength={280} disabled={busy} />
            <div className="composer-foot"><span className={promptBytes > 280 ? "over" : ""}>{promptBytes} / 280 bytes</span><button className="preview-button" type="submit" disabled={busy || !deployed || loadingMeta || !modelReady}>只读运行推理 <b>↗</b></button></div>
          </form>
          {error && <div className="error" role="alert"><b>!</b><span>{error}</span></div>}
          <div className="quick-prompts">{prompts.map((value) => <button type="button" key={value} onClick={() => setPrompt(value)}>{value}</button>)}</div>
        </div>

        <aside className="control-panel">
          <div className="panel-title"><span>REASONING MODE</span><b>04</b></div>
          {!deployed ? <div className="undeployed"><strong>尚未部署</strong><p>v4 合约和界面已准备好，等待选择测试链或主网。</p></div> : loadingMeta ? <div className="skeleton">正在读取链上推理器…</div> : !meta ? <div className="read-error"><strong>链上配置暂不可用</strong><p>没有使用缓存值冒充实时状态。</p><button type="button" onClick={() => { void loadMeta(); }}>重新读取</button></div> : <>
            {!meta.integrity && <div className="integrity-error" role="alert">知识模块代码哈希不匹配，所有操作已停用。</div>}
            {wrongChain && <button className="switch-button" type="button" onClick={switchNetwork}>切换到 {config.chainName}</button>}
            <div className="depth-toggle" role="group" aria-label="推理深度">
              <button type="button" aria-pressed={depth === 0} className={depth === 0 ? "active" : ""} onClick={() => setDepth(0)}><strong>快速</strong><span>单轮规则扫描</span></button>
              <button type="button" aria-pressed={depth === 1} className={depth === 1 ? "active" : ""} onClick={() => setDepth(1)}><strong>深度</strong><span>直到规则闭包</span></button>
            </div>
            <dl className="payment-grid reasoning-grid">
              <div><dt>规则数量</dt><dd>{meta.ruleCount}</dd></div><div><dt>轨迹上限</dt><dd>{meta.maxTraceSteps} 步</dd></div>
              <div><dt>钱包记忆</dt><dd>{walletMemory ? `${walletMemory.turns} 轮` : "连接后读取"}</dd></div><div><dt>已确认推理</dt><dd>{meta.totalChats.toString()}</dd></div>
            </dl>
            <button className="write-button" type="button" onClick={writeChat} disabled={busy || wrongChain || !account || !meta.integrity}><span>{!account ? "先连接钱包" : wrongChain ? `先切换到 ${config.chainName}` : "把推理与轨迹写入链上"}</span><b>→</b></button>
            <p className="payment-note">v4 测试核心不收代币，只支付网络 Gas。问题、回答、钱包地址和完整推理轨迹都会公开，禁止输入私钥、密码或隐私。</p>
          </>}
          <div className="cost-strip"><span>{depth === 1 ? "深度模式估算" : "快速模式估算"}</span><strong>{gasLabel}</strong></div>
          {lastTx && <a className="tx-link" href={config.explorerBaseUrl ? `${config.explorerBaseUrl}/tx/${lastTx}` : "#"} target="_blank" rel="noreferrer">查看交易 {short(lastTx, 10, 6)} ↗</a>}
        </aside>
      </section>

      <section className="evidence">
        <div className="evidence-intro"><p className="eyebrow">REPLAY, DON&apos;T BELIEVE.</p><h2>“它思考了”不能靠动画，<br />要靠每个节点重放。</h2><p>推理器锁定知识模块地址和代码哈希。同一个地址、问题、深度和历史状态，会得到同一组事实、规则步骤、结论与回答。</p></div>
        <div className="evidence-table">
          <EvidenceRow index="A" label="REASONER" value={config.chatAddress} state={meta?.integrity ? "LOCKED" : "未读取"} explorer={config.explorerBaseUrl} />
          <EvidenceRow index="B" label="KNOWLEDGE" value={meta?.knowledge} state="IMMUTABLE" explorer={config.explorerBaseUrl} />
          <EvidenceRow index="C" label="KNOWLEDGE HASH" value={meta?.knowledgeHash} state="SEMANTICS" />
          <EvidenceRow index="D" label="CODE HASH" value={meta?.knowledgeCodeHash} state="BYTECODE" />
          <EvidenceRow index="E" label="PIPELINE" value={meta?.architecture} state={`${meta?.ruleCount ?? 18} RULES`} />
        </div>
      </section>

      <section className="limits">
        <div><span>01</span><h3>覆盖所有输入，不保证事实</h3><p>它能对已知主题组合事实，也会对任何陌生问题生成结构化回答。陌生回答只是提示条件化的低置信度推测，不代表它突然拥有全世界知识。</p></div>
        <div><span>02</span><h3>Gas 买的是步骤</h3><p>深度模式允许继续应用依赖规则。只有架构定义了额外步骤，更多 Gas 才会换来更完整的结论；空烧 Gas 不会增加智力。</p></div>
        <div><span>03</span><h3>真实性边界公开</h3><p>{meta?.truthBoundary || "知识编写发生在链下；解析、事实读取、规则推导、验证、回答渲染和记忆在链上执行。"}</p></div>
      </section>

      <footer><span>TINYAI / UNIVERSAL BOUNDED ANSWERING ON EVM</span><span>{meta ? `${meta.totalChats.toString()} CONFIRMED REASONINGS` : "RESEARCH BUILD"}</span><span>ENGINE V{meta?.version ?? 4}.1</span></footer>
    </main>
  );
}

function ReasoningTrace({ result }: { result: ReasoningResult }) {
  const steps = decodeTrace(result);
  const conclusions = namesFor(result.conclusions, conclusionNames);
  return <details className="reasoning-trace">
    <summary><span>{domainNames[result.domain] || "未知"} / {queryNames[result.queryType] || "未识别"}</span><b>{result.stepCount} 步 · {(result.confidence / 100).toFixed(0)}%</b></summary>
    <div className="trace-summary">
      <span>{result.depth === 1 ? "深度闭包" : "快速扫描"}</span>
      {result.followedContext && <span>承接上轮</span>}
      <code title={result.traceHash}>轨迹 {short(result.traceHash, 10, 8)}</code>
    </div>
    <ol className="trace-steps">
      {steps.map((step) => <li key={`${step.index}-${step.word}`}>
        <i>{String(step.index).padStart(2, "0")}</i>
        <div><strong>{step.title}</strong>{step.addedFacts.length > 0 && <small>新增事实：{step.addedFacts.join(" · ")}</small>}{step.addedConclusions.length > 0 && <small className="conclusion">推出结论：{step.addedConclusions.join(" · ")}</small>}<code title={step.word}>{short(step.word, 12, 8)}</code></div>
      </li>)}
    </ol>
    <div className="trace-result"><span>最终结论</span><strong>{conclusions.length ? conclusions.join(" · ") : "没有形成可靠结论"}</strong></div>
  </details>;
}

function EvidenceRow({ index, label, value, state, explorer }: { index: string; label: string; value?: string | null; state: string; explorer?: string }) {
  const rendered = value || "等待部署地址";
  const isAddress = /^0x[0-9a-fA-F]{40}$/.test(rendered);
  return <div className="evidence-row"><b>{index}</b><span>{label}</span>{isAddress && explorer ? <a href={`${explorer}/address/${rendered}`} target="_blank" rel="noreferrer">{short(rendered, 12, 8)} ↗</a> : <code title={rendered}>{short(rendered, 14, 10)}</code>}<em>{state}</em></div>;
}
