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
  type EIP1193Provider,
  type Hash,
} from "viem";
import { intentNames, retrieverV5Abi, type DeploymentConfig } from "@/lib/contracts";

type Stage = "idle" | "connecting" | "previewing" | "signing" | "submitted" | "confirming" | "confirmed" | "failed";
type RetrievalResult = {
  response: string;
  evidence: string;
  intent: number;
  secondaryIntent: number;
  topic: number;
  queryType: number;
  classifierConfidence: number;
  matchScore: number;
  cues: bigint;
  factIds: readonly [number, number, number];
  factCount: number;
  unknown: boolean;
  negated: boolean;
  chinese: boolean;
  followedContext: boolean;
  traceHash: Hash;
  nextContext: Hash;
  trace: readonly Hash[];
};
type RetrieverMeta = {
  version: number;
  maxFacts: number;
  classifier: Address;
  modelCard: Address;
  knowledge: Address;
  knowledgeHash: Hash;
  classifierCodeHash: Hash;
  modelCardCodeHash: Hash;
  knowledgeCodeHash: Hash;
  integrity: boolean;
  totalChats: bigint;
  architecture: string;
  truthBoundary: string;
};
type WalletMemory = { turns: number; lastTopic: number; lastIntent: number; matchScore: number };
type Message = {
  id: string;
  role: "user" | "ai";
  text: string;
  mode: "preview" | "confirmed";
  retrieval?: RetrievalResult;
};
type InjectedProvider = EIP1193Provider & {
  on?: (event: string, listener: (...args: unknown[]) => void) => void;
  removeListener?: (event: string, listener: (...args: unknown[]) => void) => void;
};

declare global { interface Window { ethereum?: InjectedProvider } }

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;
const topicNames = ["未知", "身份", "链上真实性", "BSC", "人类", "Gas", "钱包", "合约", "代币", "DeFi", "NFT", "交易", "隐私", "治理", "规划", "市场", "日常对话"];
const queryNames = ["未识别", "问候", "定义", "为什么", "怎么做", "比较", "风险", "追问"];
const cueNames: Array<[bigint, string]> = [
  [1n << 0n, "AI"], [1n << 1n, "规模变化"], [1n << 2n, "管理员"], [1n << 3n, "增发"],
  [1n << 4n, "代理/升级"], [1n << 5n, "黑名单"], [1n << 6n, "流动性"], [1n << 7n, "签名"],
  [1n << 8n, "私钥"], [1n << 9n, "实时"], [1n << 10n, "价格"], [1n << 11n, "安全"],
  [1n << 12n, "规划"], [1n << 13n, "代码"],
];
const prompts = [
  "你知道什么是 BSC 吗？",
  "你知道什么是人类吗？",
  "把 Gas 提高十倍，AI 会聪明十倍吗？",
  "这个合约可以增发，而且管理员还在，安全吗？",
  "恐龙为什么灭绝？",
  "怎么做红烧肉？",
];
const stageCopy: Record<Stage, string> = {
  idle: "等待输入", connecting: "连接钱包…", previewing: "分类、检索、核验证据…", signing: "等待钱包签名…",
  submitted: "交易已提交", confirming: "等待区块确认…", confirmed: "回答与证据已写入链上", failed: "操作失败",
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

function activeCues(cues: bigint) {
  return cueNames.filter(([flag]) => (cues & flag) !== 0n).map(([, name]) => name);
}

function intentLabel(intent: number) {
  return intent === 255 ? "无" : intentNames[intent] || String(intent);
}

function traceSteps(result: RetrievalResult) {
  const facts = result.factIds.slice(0, result.factCount).map(String);
  const cues = activeCues(result.cues);
  const details = [
    `主意图 ${intentLabel(result.intent)}；次意图 ${intentLabel(result.secondaryIntent)}；分类余量 ${(result.classifierConfidence / 100).toFixed(0)}%`,
    `主题 ${topicNames[result.topic] || result.topic}；问法 ${queryNames[result.queryType] || result.queryType}；${result.negated ? "检测到否定" : "未检测到否定"}${cues.length ? `；线索 ${cues.join(" · ")}` : ""}`,
    facts.length ? `命中事实 ${facts.join(" · ")}` : "没有事实达到检索门槛",
    result.unknown ? "知识不足，停止猜测并进入委婉未知回答" : `通过 ${result.factCount} 条事实的回答门槛`,
    result.unknown ? "生成边界说明，不伪造答案" : "组合结论、依据与边界",
  ];
  const titles = ["训练分类器", "解析实体与语气", "检索不可变事实", "核验回答门槛", "组合最终回答"];
  return result.trace.map((word, index) => ({ index: index + 1, title: titles[index], detail: details[index], word }));
}

export function RetrieverConsole({ config }: { config: DeploymentConfig }) {
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
  const [meta, setMeta] = useState<RetrieverMeta | null>(null);
  const [walletMemory, setWalletMemory] = useState<WalletMemory | null>(null);
  const [prompt, setPrompt] = useState(prompts[0]);
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
  const modelReady = Boolean(meta?.integrity && meta.version === 5);

  const loadMemory = useCallback(async (user: Address) => {
    if (!config.chatAddress) return;
    const requestVersion = ++walletReadVersion.current;
    try {
      const memory = await publicClient.readContract({
        address: config.chatAddress, abi: retrieverV5Abi, functionName: "memoryOf", args: [user],
      });
      if (requestVersion !== walletReadVersion.current) return;
      setWalletMemory({ turns: memory.turns, lastTopic: memory.lastTopic, lastIntent: memory.lastIntent, matchScore: memory.matchScore });
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
      const [version, maxFacts, classifier, modelCard, knowledge, knowledgeHash, classifierCodeHash, modelCardCodeHash, knowledgeCodeHash, integrity, totalChats, architecture, truthBoundary] = await Promise.all([
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "VERSION" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "MAX_FACTS" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "classifier" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "modelCard" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "knowledge" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "KNOWLEDGE_HASH" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "classifierCodeHash" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "modelCardCodeHash" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "knowledgeCodeHash" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "integrityOk" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "totalChats" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "architecture" }),
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "truthBoundary" }),
      ]);
      const next: RetrieverMeta = { version, maxFacts, classifier, modelCard, knowledge, knowledgeHash, classifierCodeHash, modelCardCodeHash, knowledgeCodeHash, integrity, totalChats, architecture, truthBoundary };
      setMeta(next);
      return next;
    } catch (cause) {
      setError(`读取 v5 链上检索器失败：${explainError(cause)}`);
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
    }).catch(() => { /* Read-only retrieval remains available without wallet discovery. */ });
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
    if (!window.ethereum) { setError("没有检测到浏览器钱包扩展。你仍然可以免费执行只读链上问答。"); return; }
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
    if (!deployed) throw new Error("v5 检索器尚未部署到当前网络。");
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
      const callData = encodeFunctionData({ abi: retrieverV5Abi, functionName: "preview", args: [user, prompt] });
      const [result, estimated] = await Promise.all([
        publicClient.readContract({ address: config.chatAddress, abi: retrieverV5Abi, functionName: "preview", args: [user, prompt] }),
        publicClient.estimateGas({ to: config.chatAddress, data: callData, account: user }),
      ]);
      const output = result as RetrievalResult;
      setGasEstimate(estimated);
      setMessages((current) => [...current,
        { id: crypto.randomUUID(), role: "user", text: prompt, mode: "preview" },
        { id: crypto.randomUUID(), role: "ai", text: output.response, mode: "preview", retrieval: output },
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
        account, address: config.chatAddress, abi: retrieverV5Abi, functionName: "chat", args: [prompt],
      });
      const simulated = simulation.result as RetrievalResult;
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
      if (receipt.status !== "success") throw new Error("链上问答交易执行失败。");
      let eventVerified = false;
      for (const log of receipt.logs) {
        try {
          const decoded = decodeEventLog({ abi: retrieverV5Abi, data: log.data, topics: log.topics });
          if (decoded.eventName !== "RetrievedChat") continue;
          eventVerified = decoded.args.traceHash === simulated.traceHash
            && decoded.args.response === simulated.response
            && decoded.args.evidence === simulated.evidence;
        } catch { /* Ignore unrelated logs. */ }
      }
      if (!eventVerified) throw new Error("交易成功，但回答事件与签名前模拟结果不一致。");
      setMessages((current) => [...current,
        { id: crypto.randomUUID(), role: "user", text: prompt, mode: "confirmed" },
        { id: crypto.randomUUID(), role: "ai", text: simulated.response, mode: "confirmed", retrieval: simulated },
      ]);
      setStage("confirmed");
      await Promise.all([loadMeta(), loadMemory(account)]);
    } catch (cause) { setError(explainError(cause)); setStage("failed"); }
  }

  const gasLabel = gasEstimate ? `${Number(gasEstimate).toLocaleString()} gas` : "预览后显示";

  return (
    <main className="shell retriever-shell">
      <div className="noise" aria-hidden="true" />
      <header className="topbar">
        <a className="brand" href="#top" aria-label="TinyAI 首页"><span className="brand-mark">T</span><span>TINY<span>AI</span></span></a>
        <div className="network"><i className={deployed ? "pulse" : "pulse muted"} />{config.chainName}<small>{config.buildLabel}</small></div>
        <button className="wallet-button" type="button" onClick={connectWallet} disabled={stage === "connecting"}>{account ? short(account) : "连接钱包"}</button>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">TRAINED ROUTER + FACT RETRIEVAL / VERSION 05</p>
          <h1>先找事实。<br /><em>不知道就不乱说。</em></h1>
          <p className="lede">v3 训练分类器先判断你的意图，v5 再识别具体对象、否定句和风险线索，从不可变知识里取出最多三条证据。没有相关事实时，它会委婉说明能力边界，不再拿套话冒充答案。</p>
        </div>
        <div className="truth-stamp"><strong>{meta?.integrity ? "VERIFIED" : deployed ? "CHECKING" : "LOCAL"}</strong><span>CLASSIFY · RETRIEVE · VERIFY</span><b>PURE EVM</b></div>
      </section>

      <section className="workspace">
        <div className="terminal">
          <div className="terminal-head"><span><i /> RETRIEVAL TERMINAL</span><span className="stage" aria-live="polite">{stageCopy[stage]}</span></div>
          <div className="messages" aria-live="polite">
            {messages.length === 0 ? <div className="empty-state"><span>05</span><h2>问它，也检查它凭什么回答</h2><p>“只读问它”会让 RPC 节点完整运行分类、检索与组合，不花你的 Gas。能回答时显示事实编号和证据；知识不足时明确停下来。</p></div> : messages.map((message) => (
              <article className={`message ${message.role}`} key={message.id}>
                <div className="message-label">{message.role === "user" ? "YOU" : "TINYAI V5"}<span>{message.retrieval?.unknown ? `知识不足 · ${message.mode === "confirmed" ? "已确认" : "只读"}` : message.retrieval ? `找到 ${message.retrieval.factCount} 条事实 · ${message.mode === "confirmed" ? "已确认" : "只读"}` : message.mode === "confirmed" ? "已确认" : "只读"}</span></div>
                <p>{message.text}</p>
                {message.retrieval && <RetrievalTrace result={message.retrieval} />}
              </article>
            ))}
          </div>
          <form className="composer" onSubmit={preview}>
            <textarea aria-label="聊天问题" value={prompt} onChange={(event) => setPrompt(event.target.value)} placeholder="输入一个具体问题…" maxLength={280} disabled={busy} />
            <div className="composer-foot"><span className={promptBytes > 280 ? "over" : ""}>{promptBytes} / 280 bytes</span><button className="preview-button" type="submit" disabled={busy || !deployed || loadingMeta || !modelReady}>只读问它 <b>↗</b></button></div>
          </form>
          {error && <div className="error" role="alert"><b>!</b><span>{error}</span></div>}
          <div className="quick-prompts">{prompts.map((value) => <button type="button" key={value} onClick={() => setPrompt(value)}>{value}</button>)}</div>
        </div>

        <aside className="control-panel">
          <div className="panel-title"><span>RETRIEVAL STATUS</span><b>05</b></div>
          {!deployed ? <div className="undeployed"><strong>尚未部署</strong><p>v5 合约和界面已准备好，等待部署到测试网络。</p></div> : loadingMeta ? <div className="skeleton">正在读取链上分类器与知识库…</div> : !meta ? <div className="read-error"><strong>链上配置暂不可用</strong><p>没有使用缓存值冒充实时状态。</p><button type="button" onClick={() => { void loadMeta(); }}>重新读取</button></div> : <>
            {!meta.integrity && <div className="integrity-error" role="alert">分类器、模型卡或知识库代码哈希不匹配，所有操作已停用。</div>}
            {wrongChain && <button className="switch-button" type="button" onClick={switchNetwork}>切换到 {config.chainName}</button>}
            <dl className="payment-grid reasoning-grid">
              <div><dt>训练特征</dt><dd>13,531</dd></div><div><dt>单次事实上限</dt><dd>{meta.maxFacts} 条</dd></div>
              <div><dt>钱包记忆</dt><dd>{walletMemory ? `${walletMemory.turns} 轮` : "连接后读取"}</dd></div><div><dt>已确认问答</dt><dd>{meta.totalChats.toString()}</dd></div>
            </dl>
            <button className="write-button" type="button" onClick={writeChat} disabled={busy || wrongChain || !account || !meta.integrity}><span>{!account ? "先连接钱包" : wrongChain ? `先切换到 ${config.chainName}` : "把问题、回答与证据写入链上"}</span><b>→</b></button>
            <p className="payment-note">v5 测试核心不收代币，只支付网络 Gas。写入后问题、回答、钱包地址和证据永久公开；禁止输入私钥、密码、身份信息或其他隐私。</p>
          </>}
          <div className="cost-strip"><span>本次执行量估算</span><strong>{gasLabel}</strong></div>
          {lastTx && <a className="tx-link" href={config.explorerBaseUrl ? `${config.explorerBaseUrl}/tx/${lastTx}` : "#"} target="_blank" rel="noreferrer">查看交易 {short(lastTx, 10, 6)} ↗</a>}
        </aside>
      </section>

      <section className="evidence">
        <div className="evidence-intro"><p className="eyebrow">VERIFY THE MODULES.</p><h2>聪明一点，<br />但不假装无所不知。</h2><p>检索器同时锁定 v3 分类器、模型卡和 v5 知识库的地址与运行时代码哈希。网页关闭后，任何 EVM 节点仍能得到同样的回答、证据和轨迹哈希。</p></div>
        <div className="evidence-table">
          <EvidenceRow index="A" label="RETRIEVER" value={config.chatAddress} state={meta?.integrity ? "LOCKED" : "未读取"} explorer={config.explorerBaseUrl} />
          <EvidenceRow index="B" label="V3 CLASSIFIER" value={meta?.classifier} state="TRAINED" explorer={config.explorerBaseUrl} />
          <EvidenceRow index="C" label="MODEL CARD" value={meta?.modelCard} state="IMMUTABLE" explorer={config.explorerBaseUrl} />
          <EvidenceRow index="D" label="V5 KNOWLEDGE" value={meta?.knowledge} state="IMMUTABLE" explorer={config.explorerBaseUrl} />
          <EvidenceRow index="E" label="KNOWLEDGE HASH" value={meta?.knowledgeHash} state="SEMANTICS" />
          <EvidenceRow index="F" label="CLASSIFIER CODE" value={meta?.classifierCodeHash} state="BYTECODE" />
          <EvidenceRow index="G" label="KNOWLEDGE CODE" value={meta?.knowledgeCodeHash} state="BYTECODE" />
        </div>
      </section>

      <section className="limits">
        <div><span>01</span><h3>不会的就委婉承认</h3><p>未知问题不会再被强行归进“规划”或其他万能类别。没有事实通过门槛时，只解释知识边界，并提示你补充具体对象与场景。</p></div>
        <div><span>02</span><h3>聪明来自结构，不是空烧 Gas</h3><p>训练分类负责理解意图，实体线索负责纠偏，知识检索负责提供依据。增加 Gas 只有在增加候选事实、验证步骤或模型规模时才可能提升能力。</p></div>
        <div><span>03</span><h3>依然不是通用大模型</h3><p>训练和知识编写发生在链下；分类、检索、组合、输出和记忆在链上执行。合约公开的原始边界声明可由任何节点读取。</p></div>
      </section>

      <footer><span>TINYAI / TRAINED RETRIEVAL ON EVM</span><span>{meta ? `${meta.totalChats.toString()} CONFIRMED RETRIEVALS` : "RESEARCH BUILD"}</span><span>ENGINE V{meta?.version ?? 5}</span></footer>
    </main>
  );
}

function RetrievalTrace({ result }: { result: RetrievalResult }) {
  const steps = traceSteps(result);
  const factIds = result.factIds.slice(0, result.factCount);
  return <details className="reasoning-trace">
    <summary><span>{topicNames[result.topic] || "未知"} / {queryNames[result.queryType] || "未识别"}</span><b>{result.unknown ? "知识不足" : `${result.factCount} 条事实`} · {(result.matchScore / 100).toFixed(0)}%</b></summary>
    <div className="trace-summary">
      <span>训练意图：{intentLabel(result.intent)}</span>
      <span>分类余量 {(result.classifierConfidence / 100).toFixed(0)}%</span>
      {result.followedContext && <span>承接上轮</span>}
      {result.negated && <span>已识别否定</span>}
      <code title={result.traceHash}>轨迹 {short(result.traceHash, 10, 8)}</code>
    </div>
    <ol className="trace-steps">
      {steps.map((step) => <li key={`${step.index}-${step.word}`}>
        <i>{String(step.index).padStart(2, "0")}</i>
        <div><strong>{step.title}</strong><small>{step.detail}</small><code title={step.word}>{short(step.word, 12, 8)}</code></div>
      </li>)}
    </ol>
    <div className="trace-result"><span>{result.unknown ? "为什么没有回答" : `链上证据 · ${factIds.join(" · ")}`}</span><strong>{result.evidence}</strong></div>
  </details>;
}

function EvidenceRow({ index, label, value, state, explorer }: { index: string; label: string; value?: string | null; state: string; explorer?: string }) {
  const rendered = value || "等待部署地址";
  const isAddress = /^0x[0-9a-fA-F]{40}$/.test(rendered);
  return <div className="evidence-row"><b>{index}</b><span>{label}</span>{isAddress && explorer ? <a href={`${explorer}/address/${rendered}`} target="_blank" rel="noreferrer">{short(rendered, 12, 8)} ↗</a> : <code title={rendered}>{short(rendered, 14, 10)}</code>}<em>{state}</em></div>;
}
