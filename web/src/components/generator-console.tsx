"use client";

import Link from "next/link";
import { FormEvent, KeyboardEvent, useEffect, useMemo, useRef, useState } from "react";
import { createPublicClient, defineChain, http, type Address } from "viem";
import { generatorV6Abi, type DeploymentConfig } from "@/lib/contracts";
import styles from "./generator-console.module.css";

type ReadState = "checking" | "ready" | "reading" | "error";
type Message = { id: string; role: "user" | "assistant"; text: string };
type GenerationResult = { response: string };

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;
const starters = ["你是什么？", "什么是 BSC？", "Gas 提高十倍会更聪明吗？"];

function explainError(error: unknown) {
  const value = error as { shortMessage?: string; message?: string };
  const message = value?.shortMessage || value?.message || "链上调用暂时没有返回结果";
  if (/timeout|timed out|upstream/i.test(message)) return "链上节点响应超时，请稍后再试。";
  if (/network|fetch|connection/i.test(message)) return "暂时无法连接链上节点，请检查网络后重试。";
  return message.split("\n")[0].slice(0, 180);
}

export function GeneratorConsole({ config }: { config: DeploymentConfig }) {
  const displayChainName = config.chainName.replace(/\s+v\d+$/i, "");
  const chain = useMemo(() => defineChain({
    id: config.chainId,
    name: config.chainName,
    nativeCurrency: { name: config.nativeSymbol, symbol: config.nativeSymbol, decimals: 18 },
    rpcUrls: { default: { http: ["/api/rpc"] } },
  }), [config]);
  const publicClient = useMemo(() => createPublicClient({ chain, transport: http("/api/rpc") }), [chain]);
  const [prompt, setPrompt] = useState("");
  const [messages, setMessages] = useState<Message[]>([]);
  const [state, setState] = useState<ReadState>(config.chatAddress ? "checking" : "error");
  const [error, setError] = useState(config.chatAddress ? "" : "当前网络还没有配置 TinyAI 合约地址。");
  const endRef = useRef<HTMLDivElement>(null);
  const promptBytes = new TextEncoder().encode(prompt).length;

  useEffect(() => {
    if (!config.chatAddress) return;
    let cancelled = false;
    void Promise.all([
      publicClient.readContract({ address: config.chatAddress, abi: generatorV6Abi, functionName: "VERSION" }),
      publicClient.readContract({ address: config.chatAddress, abi: generatorV6Abi, functionName: "integrityOk" }),
    ]).then(([version, integrity]) => {
      if (cancelled) return;
      if (version !== 6 || !integrity) throw new Error("链上模型完整性检查未通过。");
      setState("ready");
      setError("");
    }).catch((cause) => {
      if (cancelled) return;
      setState("error");
      setError(explainError(cause));
    });
    return () => { cancelled = true; };
  }, [config.chatAddress, publicClient]);

  useEffect(() => { endRef.current?.scrollIntoView({ block: "end" }); }, [messages, state]);

  async function send(event?: FormEvent) {
    event?.preventDefault();
    const question = prompt.trim();
    if (!question || state === "reading") return;
    if (!config.chatAddress) { setState("error"); setError("当前网络还没有配置 TinyAI 合约地址。"); return; }
    if (promptBytes > 280) { setState("error"); setError("问题请控制在 280 字节以内。"); return; }

    setMessages((current) => [...current, { id: crypto.randomUUID(), role: "user", text: question }]);
    setPrompt("");
    setState("reading");
    setError("");
    try {
      const result = await publicClient.readContract({
        address: config.chatAddress,
        abi: generatorV6Abi,
        functionName: "preview",
        args: [ZERO_ADDRESS, question],
      }) as GenerationResult;
      setMessages((current) => [...current, { id: crypto.randomUUID(), role: "assistant", text: result.response }]);
      setState("ready");
    } catch (cause) {
      setState("error");
      setError(explainError(cause));
    }
  }

  function handleKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      void send();
    }
  }

  const ready = state === "ready" || state === "reading";
  return <main className={styles.page}>
    <header className={styles.header}>
      <Link className={styles.brand} href="/" aria-label="TinyAI 首页">
        <span className={styles.logo} aria-hidden="true">T</span>
        <span>TinyAI</span>
      </Link>
      <div className={styles.headerRight}>
        <span className={styles.network}><i className={ready ? styles.online : styles.offline} />{displayChainName}</span>
        <Link className={styles.docsLink} href="/protocol">Protocol</Link>
        <Link className={styles.docsLink} href="/market">Market</Link>
        <Link className={styles.docsLink} href="/docs">Docs</Link>
      </div>
    </header>

    <section className={styles.chat} aria-label="TinyAI 对话窗口">
      <div className={styles.messages} aria-live="polite">
        {messages.length === 0 && <div className={styles.welcome}>
          <div className={styles.aiMark}>T</div>
          <h1>你好，我是 TinyAI</h1>
          <p>一个运行在 BSC 智能合约里的链上 AI。你可以直接和我对话。</p>
          <div className={styles.starters}>{starters.map((starter) => <button type="button" key={starter} onClick={() => setPrompt(starter)}>{starter}</button>)}</div>
        </div>}
        {messages.map((message) => <article className={`${styles.message} ${message.role === "user" ? styles.user : styles.assistant}`} key={message.id}>
          <span>{message.role === "user" ? "你" : "TinyAI"}</span>
          <p>{message.text}</p>
        </article>)}
        {state === "reading" && <article className={`${styles.message} ${styles.assistant}`}>
          <span>TinyAI</span><p className={styles.thinking}><i /><i /><i /></p>
        </article>}
        <div ref={endRef} />
      </div>

      <div className={styles.composerArea}>
        {error && <div className={styles.error} role="alert"><span>{error}</span><button type="button" onClick={() => { setError(""); setState(config.chatAddress ? "ready" : "error"); }}>关闭</button></div>}
        <form className={styles.composer} onSubmit={send}>
          <textarea
            aria-label="输入问题"
            value={prompt}
            onChange={(event) => setPrompt(event.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={state === "checking" ? "正在连接链上模型…" : "给 TinyAI 发消息"}
            rows={1}
            disabled={state === "checking" || state === "reading"}
          />
          <button type="submit" aria-label="发送消息" disabled={!prompt.trim() || promptBytes > 280 || state !== "ready"}>↑</button>
        </form>
        <p className={promptBytes > 280 ? styles.over : ""}>回答由智能合约直接计算 · {promptBytes}/280 bytes</p>
      </div>
    </section>
  </main>;
}
