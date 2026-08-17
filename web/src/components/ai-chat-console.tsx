"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  decodeEventLog,
  defineChain,
  http,
  parseAbiItem,
  type Address,
  type EIP1193Provider,
  type Hash,
  type TransactionReceipt,
} from "viem";
import { componentCards } from "@/lib/component-catalog";
import { componentsAbi, protocolAbi, type DeploymentConfig } from "@/lib/contracts";
import { canAutoAddNetwork, switchOrAddNetwork } from "@/lib/wallet-network";
import { GitHubLink } from "./github-link";
import styles from "./ai-chat-console.module.css";

type InjectedProvider = EIP1193Provider & {
  on?: (event: string, listener: (...args: unknown[]) => void) => void;
  removeListener?: (event: string, listener: (...args: unknown[]) => void) => void;
};

type Stage = "idle" | "loading" | "connecting" | "simulating" | "signing" | "broadcasting" | "confirming" | "success" | "error";
type Access = "checking" | "wallet" | "owner" | "denied" | "missing";
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
type AIRecord = { owner: Address; name: string; state: AIState; memory: Hash[] };
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
type Message = { id: string; role: "user" | "ai"; text: string; meta?: string };

const ZERO_HASH = `0x${"0".repeat(64)}` as Hash;
const CHAT_LOG_SPAN = 5_000n;
const MAX_VISIBLE_TURNS = 50;
const BSC_TRANSACTION_GAS_CAP = 16_777_216n;
const DIAGNOSTIC_CALL_GAS_LIMIT = 45_000_000n;
const CHAT_GAS_BUFFER = 250_000n;
const MIN_CHAT_GAS_LIMIT = 1_000_000n;
const BROADCAST_TIMEOUT_MS = 30_000;
const RECEIPT_TIMEOUT_MS = 5 * 60_000;
const PENDING_CHAT_PREFIX = "tinyai:pending-chat:v1";
const aiChatEvent = parseAbiItem("event AIChat(uint256 indexed aiId, address indexed speaker, uint32 indexed turn, uint32 brainVersion, uint8 topic, uint8 variant, bool unknown, bool neuralGenerated, string prompt, string response, bytes32 traceHash, bytes32 memoryRoot)");
const prompts = ["你是谁？", "你的性格是什么？", "你还记得多少次对话？"];

type PendingChat = { hash: Hash; createdAt: number };

class BroadcastMissingError extends Error {
  constructor() {
    super("钱包已经完成签名，但 BSC 节点没有收到这笔交易；本次没有产生链上 Gas，请重新发送。");
    this.name = "BroadcastMissingError";
  }
}

class BrainGasCapError extends Error {
  constructor() {
    super(
      "当前大脑的一次推理超过 BSC 16,777,216 Gas 的单笔硬上限。前端已在打开钱包前停止，本次没有交易，也不会产生 Gas；需要升级到低 Gas 大脑后才能继续对话。",
    );
    this.name = "BrainGasCapError";
  }
}

function bufferedChatGas(estimate: bigint) {
  const buffered = estimate + estimate / 2n + CHAT_GAS_BUFFER;
  const withFloor = buffered < MIN_CHAT_GAS_LIMIT ? MIN_CHAT_GAS_LIMIT : buffered;
  return withFloor > BSC_TRANSACTION_GAS_CAP ? BSC_TRANSACTION_GAS_CAP : withFloor;
}

function pendingChatKey(chainId: number, protocolAddress: Address, aiId: bigint, account: Address) {
  return `${PENDING_CHAT_PREFIX}:${chainId}:${protocolAddress.toLowerCase()}:${aiId}:${account.toLowerCase()}`;
}

function readPendingChat(key: string): PendingChat | null {
  try {
    const value = JSON.parse(window.localStorage.getItem(key) || "null") as Partial<PendingChat> | null;
    if (!value || typeof value.hash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(value.hash)) return null;
    if (typeof value.createdAt !== "number" || !Number.isFinite(value.createdAt)) return null;
    return { hash: value.hash as Hash, createdAt: value.createdAt };
  } catch {
    return null;
  }
}

function writePendingChat(key: string, hash: Hash, createdAt = Date.now()) {
  try {
    window.localStorage.setItem(key, JSON.stringify({ hash, createdAt } satisfies PendingChat));
  } catch {
    // The chain remains authoritative when browser storage is unavailable.
  }
}

function clearPendingChat(key: string) {
  try {
    window.localStorage.removeItem(key);
  } catch {
    // Storage failure must not hide a confirmed chain result.
  }
}

function chatEventFromReceipt(receipt: TransactionReceipt, aiId: bigint) {
  for (const log of receipt.logs) {
    try {
      const decoded = decodeEventLog({ abi: protocolAbi, data: log.data, topics: log.topics });
      if (decoded.eventName === "AIChat" && decoded.args.aiId === aiId) return decoded.args;
    } catch {
      // A receipt may include unrelated logs.
    }
  }
  return null;
}

function delay(milliseconds: number) {
  return new Promise<void>((resolve) => window.setTimeout(resolve, milliseconds));
}

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
  if (/timed out|timeout/i.test(message)) return "交易仍未确认；交易哈希已经保存，刷新或重新进入房间后会继续恢复。";
  if (/insufficient funds/i.test(message)) return "钱包 BNB 不足，无法支付这次交易的 Gas。";
  if (/NotAIOwner|not.*owner|caller is not token owner/i.test(message)) return "只有这只 AI 的当前主人可以执行这个操作。";
  if (/ComponentWouldBeWasted/i.test(message)) return "这枚组件会超过这只 AI 的属性上限，因此合约拒绝浪费组件。";
  if (/ERC1155InsufficientBalance|insufficient balance/i.test(message)) return "当前钱包没有足够的这种组件。";
  if (/wrong chain|chain.*mismatch|network/i.test(message)) return "钱包网络不匹配，请先切换到页面显示的网络。";
  if (/user rejected|denied/i.test(message)) return "你在钱包里取消了这次操作。";
  return message.split("\n")[0].slice(0, 240);
}

function stageText(stage: Stage, action: string) {
  if (stage === "loading") return "正在验证主人身份并读取链上档案";
  if (stage === "connecting") return "正在连接钱包";
  if (stage === "simulating") return `正在模拟${action}`;
  if (stage === "signing") return `等待钱包确认${action}`;
  if (stage === "broadcasting") return "钱包已签名，正在确认 BSC 已接收交易";
  if (stage === "confirming") return "BSC 已接收交易，等待区块确认";
  if (stage === "success") return `${action}已确认`;
  return action;
}

export function AIChatConsole({ aiId, config }: { aiId: string; config: DeploymentConfig }) {
  const id = BigInt(aiId);
  const protocolAddress = config.protocolAddress || null;
  const componentsAddress = config.componentsAddress || null;
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
  const [walletReady, setWalletReady] = useState(false);
  const [access, setAccess] = useState<Access>("checking");
  const [record, setRecord] = useState<AIRecord | null>(null);
  const [definitions, setDefinitions] = useState<Record<number, Definition>>({});
  const [componentBalances, setComponentBalances] = useState<Record<number, bigint>>({});
  const [prompt, setPrompt] = useState("");
  const [messages, setMessages] = useState<Message[]>([]);
  const [stage, setStage] = useState<Stage>("idle");
  const [action, setAction] = useState("等待操作");
  const [error, setError] = useState("");
  const [lastTx, setLastTx] = useState<Hash | null>(null);
  const recoveringHash = useRef<Hash | null>(null);

  const activePendingKey = useMemo(() => {
    if (!account || !protocolAddress) return null;
    return pendingChatKey(config.chainId, protocolAddress, id, account);
  }, [account, config.chainId, id, protocolAddress]);

  const wrongChain = account !== null && walletChain !== null && walletChain !== config.chainId;
  const ownsAI = Boolean(account && record && account.toLowerCase() === record.owner.toLowerCase());
  const canCommit = Boolean(access === "owner" && ownsAI && !wrongChain);
  const busy = !["idle", "success", "error"].includes(stage);
  const promptBytes = useMemo(() => new TextEncoder().encode(prompt.trim()).length, [prompt]);
  const switchLabel = canAutoAddNetwork(config.walletRpcUrl)
    ? `添加并切换到 ${config.chainName}`
    : `切换到 ${config.chainName}`;

  const loadChatHistory = useCallback(async (turns: number) => {
    if (!protocolAddress || turns === 0) return [] as Message[];
    const deploymentBlock = BigInt(config.protocolFromBlock || 0);
    const latestBlock = await publicClient.getBlockNumber();
    const firstBlock = deploymentBlock > 0n ? deploymentBlock : latestBlock;
    const logs: Awaited<ReturnType<typeof publicClient.getLogs<typeof aiChatEvent>>> = [];
    let cursor = latestBlock;

    while (cursor >= firstBlock && logs.length < Math.min(turns, MAX_VISIBLE_TURNS)) {
      const fromBlock = cursor > firstBlock + CHAT_LOG_SPAN ? cursor - CHAT_LOG_SPAN : firstBlock;
      const page = await publicClient.getLogs({
        address: protocolAddress,
        event: aiChatEvent,
        args: { aiId: id },
        fromBlock,
        toBlock: cursor,
      });
      logs.push(...page);
      if (fromBlock === firstBlock) break;
      cursor = fromBlock - 1n;
    }

    return logs
      .sort((a, b) => {
        const left = a.args.turn ?? 0;
        const right = b.args.turn ?? 0;
        return left - right;
      })
      .slice(-MAX_VISIBLE_TURNS)
      .flatMap((log): Message[] => {
        const turn = log.args.turn;
        const promptText = log.args.prompt;
        const responseText = log.args.response;
        const brainVersion = log.args.brainVersion;
        if (turn === undefined || promptText === undefined || responseText === undefined || brainVersion === undefined) return [];
        return [
          { id: `turn-${turn}-user`, role: "user", text: promptText },
          { id: `turn-${turn}-ai`, role: "ai", text: responseText, meta: `Turn ${turn} · Brain V${brainVersion} · 已写入 EVM` },
        ];
      });
  }, [config.protocolFromBlock, id, protocolAddress, publicClient]);

  const loadAI = useCallback(async (ownerAccount: Address, quiet = false, refreshHistory = !quiet) => {
    if (!protocolAddress) {
      setAccess("missing");
      setStage("error");
      setError("当前环境没有配置 TinyAI Protocol 地址。");
      return;
    }
    if (!quiet) {
      setAccess("checking");
      setStage("loading");
    }
    setError("");
    try {
      const owner = await publicClient.readContract({
        address: protocolAddress,
        abi: protocolAbi,
        functionName: "ownerOf",
        args: [id],
      });
      if (owner.toLowerCase() !== ownerAccount.toLowerCase()) {
        setRecord(null);
        setDefinitions({});
        setComponentBalances({});
        setAccess("denied");
        setStage("idle");
        return;
      }
      const [name, rawState] = await Promise.all([
        publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "aiName", args: [id] }),
        publicClient.readContract({ address: protocolAddress, abi: protocolAbi, functionName: "aiState", args: [id] }),
      ]);
      const state = rawState as AIState;
      const memoryPromise = Promise.all(Array.from({ length: state.memoryCapacity }, (_, slot) => publicClient.readContract({
        address: protocolAddress,
        abi: protocolAbi,
        functionName: "memoryAt",
        args: [id, slot],
      })));
      const componentPromise = componentsAddress
        ? Promise.all(componentCards.map(async ({ id: componentId }) => {
          const [definition, balance] = await Promise.all([
            publicClient.readContract({
              address: componentsAddress,
              abi: componentsAbi,
              functionName: "definition",
              args: [BigInt(componentId)],
            }),
            publicClient.readContract({
              address: componentsAddress,
              abi: componentsAbi,
              functionName: "balanceOf",
              args: [ownerAccount, BigInt(componentId)],
            }),
          ]);
          return { componentId, definition: definition as Definition, balance };
        }))
        : Promise.resolve([]);
      const historyPromise = refreshHistory
        ? loadChatHistory(state.turns)
          .then((history) => ({ messages: history, error: "" }))
          .catch((cause) => ({ messages: null, error: explainError(cause) }))
        : Promise.resolve<{ messages: Message[] | null; error: string }>({ messages: null, error: "" });
      const [memory, componentData, historyResult] = await Promise.all([memoryPromise, componentPromise, historyPromise]);
      const nextDefinitions: Record<number, Definition> = {};
      const nextBalances: Record<number, bigint> = {};
      for (const item of componentData) {
        nextDefinitions[item.componentId] = item.definition;
        nextBalances[item.componentId] = item.balance;
      }
      setRecord({ owner, name, state, memory });
      setDefinitions(nextDefinitions);
      setComponentBalances(nextBalances);
      if (historyResult.messages !== null) setMessages(historyResult.messages);
      setAccess("owner");
      if (!quiet && historyResult.error) {
        setError(`AI 档案已读取，但对话历史恢复失败：${historyResult.error}`);
        setStage("error");
      } else if (!quiet) {
        setStage("idle");
      }
    } catch (cause) {
      setRecord(null);
      setDefinitions({});
      setComponentBalances({});
      const detail = explainError(cause);
      if (/ownerOf|ERC721Nonexistent|nonexistent token|owner query/i.test(detail)) {
        setAccess("missing");
        setError(`TinyAI #${aiId} 还没有被 Mint。`);
      } else {
        setAccess("missing");
        setError(`读取 TinyAI #${aiId} 失败：${detail}`);
      }
      setStage("error");
    }
  }, [aiId, componentsAddress, id, loadChatHistory, protocolAddress, publicClient]);

  const waitForBroadcast = useCallback(async (hash: Hash) => {
    const deadline = Date.now() + BROADCAST_TIMEOUT_MS;
    while (Date.now() < deadline) {
      try {
        await publicClient.getTransaction({ hash });
        return;
      } catch {
        await delay(1_500);
      }
    }
    throw new BroadcastMissingError();
  }, [publicClient]);

  const finishConfirmedChat = useCallback(async (receipt: TransactionReceipt, ownerAccount: Address, storageKey: string) => {
    setLastTx(receipt.transactionHash);
    if (receipt.status !== "success") {
      clearPendingChat(storageKey);
      throw new Error("聊天交易已经上链，但执行失败；合约状态和对话记录都没有改变。");
    }
    if (!chatEventFromReceipt(receipt, id)) {
      clearPendingChat(storageKey);
      throw new Error("交易已确认，但回执中没有找到这只 AI 的对话事件。");
    }
    clearPendingChat(storageKey);
    await loadAI(ownerAccount, true, true);
    setPrompt("");
    setAction("对话与成长");
    setStage("success");
  }, [id, loadAI]);

  const recoverPendingChat = useCallback(async () => {
    if (!account || !activePendingKey || !canCommit) return;
    const pending = readPendingChat(activePendingKey);
    if (!pending || recoveringHash.current === pending.hash) return;
    recoveringHash.current = pending.hash;
    setLastTx(pending.hash);
    setError("");
    setAction("恢复待确认对话");
    try {
      let receipt: TransactionReceipt;
      try {
        receipt = await publicClient.getTransactionReceipt({ hash: pending.hash });
      } catch {
        setStage("broadcasting");
        await waitForBroadcast(pending.hash);
        setStage("confirming");
        receipt = await publicClient.waitForTransactionReceipt({
          hash: pending.hash,
          confirmations: 1,
          timeout: RECEIPT_TIMEOUT_MS,
          onReplaced: ({ transaction }) => {
            setLastTx(transaction.hash);
            writePendingChat(activePendingKey, transaction.hash, pending.createdAt);
          },
        });
      }
      await finishConfirmedChat(receipt, account, activePendingKey);
    } catch (cause) {
      if (cause instanceof BroadcastMissingError) clearPendingChat(activePendingKey);
      setStage("error");
      setError(explainError(cause));
    } finally {
      recoveringHash.current = null;
    }
  }, [account, activePendingKey, canCommit, finishConfirmedChat, publicClient, waitForBroadcast]);

  useEffect(() => {
    const injected = provider();
    if (!injected) {
      const task = window.setTimeout(() => {
        setWalletReady(true);
        setAccess("wallet");
      }, 0);
      return () => window.clearTimeout(task);
    }
    let cancelled = false;
    const accountsChanged = (...args: unknown[]) => {
      const next = ((args[0] as string[])?.[0] as Address) || null;
      setAccount(next);
      setRecord(null);
      setMessages([]);
      setLastTx(null);
      setError("");
      recoveringHash.current = null;
      setAccess(next ? "checking" : "wallet");
    };
    const chainChanged = (...args: unknown[]) => setWalletChain(Number(BigInt(args[0] as string)));
    const disconnected = () => {
      setAccount(null);
      setWalletChain(null);
      setRecord(null);
      setMessages([]);
      setLastTx(null);
      setError("");
      recoveringHash.current = null;
      setAccess("wallet");
    };
    injected.on?.("accountsChanged", accountsChanged);
    injected.on?.("chainChanged", chainChanged);
    injected.on?.("disconnect", disconnected);
    void Promise.all([
      injected.request({ method: "eth_accounts" }) as Promise<string[]>,
      injected.request({ method: "eth_chainId" }) as Promise<string>,
    ]).then(([accounts, chainId]) => {
      if (cancelled) return;
      const selected = (accounts?.[0] as Address) || null;
      setAccount(selected);
      setWalletChain(Number(BigInt(chainId)));
      setAccess(selected ? "checking" : "wallet");
    }).catch(() => {
      if (!cancelled) setAccess("wallet");
    }).finally(() => {
      if (!cancelled) setWalletReady(true);
    });
    return () => {
      cancelled = true;
      injected.removeListener?.("accountsChanged", accountsChanged);
      injected.removeListener?.("chainChanged", chainChanged);
      injected.removeListener?.("disconnect", disconnected);
    };
  }, []);

  useEffect(() => {
    if (!walletReady) return;
    const task = window.setTimeout(() => {
      if (account) {
        void loadAI(account);
      } else {
        setRecord(null);
        setAccess("wallet");
        setStage("idle");
      }
    }, 0);
    return () => window.clearTimeout(task);
  }, [account, loadAI, walletReady]);

  useEffect(() => {
    if (!canCommit || !activePendingKey || !readPendingChat(activePendingKey)) return;
    const task = window.setTimeout(() => { void recoverPendingChat(); }, 0);
    return () => window.clearTimeout(task);
  }, [activePendingKey, canCommit, recoverPendingChat]);

  async function connectWallet() {
    const injected = provider();
    setError("");
    if (!injected) {
      setStage("error");
      setError("没有检测到浏览器钱包。安装或打开钱包扩展后再连接。");
      return;
    }
    setStage("connecting");
    try {
      const wallet = createWalletClient({ chain, transport: custom(injected) });
      const [selected] = await wallet.requestAddresses();
      setAccount(selected);
      setWalletChain(await wallet.getChainId());
      setAccess("checking");
      setStage("idle");
    } catch (cause) {
      setStage("error");
      setError(explainError(cause));
    }
  }

  async function switchNetwork() {
    const injected = provider();
    if (!injected) return;
    setError("");
    setStage("connecting");
    setAction("切换钱包网络");
    try {
      setWalletChain(await switchOrAddNetwork(injected, config));
      setStage("idle");
    } catch (cause) {
      setStage("error");
      setError(`切换网络失败：${explainError(cause)}`);
    }
  }

  function validQuestion() {
    if (!prompt.trim()) {
      setError("先输入一个问题。");
      setStage("error");
      return null;
    }
    if (promptBytes > 280) {
      setError("问题超过合约允许的 280 字节。");
      setStage("error");
      return null;
    }
    return prompt.trim();
  }

  async function commit(event: FormEvent) {
    event.preventDefault();
    const question = validQuestion();
    const injected = provider();
    if (!question || !protocolAddress || !record) return;
    if (!account || !injected) {
      setStage("error");
      setError("先连接拥有这只 AI 的钱包。");
      return;
    }
    if (!ownsAI) {
      setStage("error");
      setError("当前钱包不是这只 AI 的主人。");
      return;
    }
    if (wrongChain) {
      setStage("error");
      setError(`请先切换到 ${config.chainName}。`);
      return;
    }
    const storageKey = pendingChatKey(config.chainId, protocolAddress, id, account);
    if (readPendingChat(storageKey)) {
      await recoverPendingChat();
      return;
    }
    setError("");
    setLastTx(null);
    setAction("对话与成长");
    setStage("simulating");
    try {
      let simulation;
      try {
        simulation = await publicClient.simulateContract({
          account,
          address: protocolAddress,
          abi: protocolAbi,
          functionName: "chatAI",
          args: [id, question],
          gas: BSC_TRANSACTION_GAS_CAP,
        });
      } catch (capCause) {
        let succeedsOutsideTransactionCap = false;
        try {
          await publicClient.simulateContract({
            account,
            address: protocolAddress,
            abi: protocolAbi,
            functionName: "chatAI",
            args: [id, question],
            gas: DIAGNOSTIC_CALL_GAS_LIMIT,
          });
          succeedsOutsideTransactionCap = true;
        } catch {
          // Preserve the original contract error when more gas does not make the call valid.
        }
        if (succeedsOutsideTransactionCap) throw new BrainGasCapError();
        throw capCause;
      }
      let chatGasLimit = BSC_TRANSACTION_GAS_CAP;
      try {
        const estimatedGas = await publicClient.estimateContractGas({
          account,
          address: protocolAddress,
          abi: protocolAbi,
          functionName: "chatAI",
          args: [id, question],
        });
        chatGasLimit = bufferedChatGas(estimatedGas);
      } catch {
        // A successful cap-bounded simulation is authoritative; keep the legal cap as a safe fallback.
      }
      const wallet = createWalletClient({ account, chain, transport: custom(injected) });
      setStage("signing");
      const hash = await wallet.writeContract({ ...simulation.request, gas: chatGasLimit });
      setLastTx(hash);
      writePendingChat(storageKey, hash);
      setStage("broadcasting");
      await waitForBroadcast(hash);
      setStage("confirming");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash,
        confirmations: 1,
        timeout: RECEIPT_TIMEOUT_MS,
        onReplaced: ({ transaction }) => {
          setLastTx(transaction.hash);
          const pending = readPendingChat(storageKey);
          writePendingChat(storageKey, transaction.hash, pending?.createdAt);
        },
      });
      await finishConfirmedChat(receipt, account, storageKey);
    } catch (cause) {
      if (cause instanceof BroadcastMissingError) clearPendingChat(storageKey);
      setStage("error");
      setError(explainError(cause));
    }
  }

  async function fuseComponent(componentId: number) {
    const injected = provider();
    const item = componentCards.find((candidate) => candidate.id === componentId);
    if (!item || !protocolAddress || !record || !account || !injected) return;
    if (!ownsAI) {
      setStage("error");
      setError("当前钱包不是这只 AI 的主人。");
      return;
    }
    if (wrongChain) {
      setStage("error");
      setError(`请先切换到 ${config.chainName}。`);
      return;
    }
    setError("");
    setLastTx(null);
    setAction(`把${item.name}融合到 ${record.name}`);
    setStage("simulating");
    try {
      const simulation = await publicClient.simulateContract({
        account,
        address: protocolAddress,
        abi: protocolAbi,
        functionName: "fuseComponent",
        args: [id, BigInt(componentId), 1n],
      });
      const wallet = createWalletClient({ account, chain, transport: custom(injected) });
      setStage("signing");
      const hash = await wallet.writeContract(simulation.request);
      setLastTx(hash);
      setStage("confirming");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash,
        confirmations: 1,
        onReplaced: ({ transaction }) => setLastTx(transaction.hash),
      });
      if (receipt.status !== "success") throw new Error("融合交易执行失败。");
      await loadAI(account, true);
      setStage("success");
    } catch (cause) {
      setStage("error");
      setError(explainError(cause));
    }
  }

  const born = record ? new Date(Number(record.state.bornAt) * 1000).toLocaleDateString("zh-CN") : "-";
  const activeMemory = record?.memory.filter((slot) => slot !== ZERO_HASH) || [];
  const lockTitle = !walletReady || access === "checking"
    ? "正在验证主人身份"
    : access === "denied"
      ? "这只 AI 不属于当前钱包"
      : access === "missing"
        ? `TinyAI #${aiId} 不存在`
        : "连接主人钱包后进入";
  const lockText = access === "denied"
    ? "房间入口只向当前 NFT 持有人开放。请切换到拥有它的钱包，或者回到“我的 AI”选择属于你的 AI。"
    : access === "missing"
      ? "请回到 Mint 页面创建一只 AI，或在“我的 AI”中打开已经持有的 AI。"
      : "这里不提供公共预览，也不允许访客保存会话。连接钱包后会先核对链上 ownerOf，再读取房间内容。";

  return <main className={styles.page}>
    <header className={styles.header}>
      <Link className={styles.brand} href="/protocol"><span className={styles.mark}>T</span><span>TinyAI</span></Link>
      <nav><Link href="/protocol">Mint</Link><Link href="/my-ai">我的 AI</Link><Link href="/market">Market</Link><GitHubLink /><Link href="/docs">Docs</Link></nav>
      <div className={styles.walletArea}>
        <span><i className={deployed ? styles.online : styles.offline} />{config.chainName}</span>
        <button type="button" onClick={connectWallet} disabled={stage === "connecting"}>{account ? short(account) : "连接钱包"}</button>
      </div>
    </header>

    {wrongChain && <section className={styles.networkNotice} role="alert">
      <div><strong>钱包网络不匹配</strong><p>主人身份已按 {config.chainName} 读取；发起对话或融合前请切换到 Chain {config.chainId}。</p></div>
      <button type="button" onClick={switchNetwork} disabled={busy}>{switchLabel}</button>
    </section>}

    {(error || !["idle", "loading"].includes(stage)) && <section className={`${styles.status} ${error ? styles.statusError : ""}`} aria-live="polite">
      <span>{error || stageText(stage, action)}</span>
      {lastTx && config.explorerBaseUrl && <a href={`${config.explorerBaseUrl}/tx/${lastTx}`} target="_blank" rel="noreferrer">查看交易 ↗</a>}
      {(error || stage === "success") && <button type="button" onClick={() => { setError(""); setStage("idle"); }}>关闭</button>}
    </section>}

    {access !== "owner" || !record ? <section className={styles.lockedRoom}>
      <div className={styles.lockMark}>T</div>
      <p>PRIVATE AI ROOM / #{aiId.padStart(4, "0")}</p>
      <h1>{lockTitle}</h1>
      <span>{lockText}</span>
      <div>
        {!account && <button type="button" onClick={connectWallet} disabled={stage === "connecting"}>连接钱包</button>}
        <Link href="/my-ai">返回我的 AI</Link>
        {access === "missing" && <Link href="/protocol">前往 Mint</Link>}
      </div>
    </section> : <div className={styles.workspace}>
      <aside className={styles.profile}>
        <div className={styles.profileLabel}><span>OWNER-ONLY AI ROOM</span><b>#{aiId.padStart(4, "0")}</b></div>
        <div className={styles.avatar}>T<span>AI #{aiId}</span></div>
        <div className={styles.identity}><p>THIS AI BELONGS TO</p><h1>{record.name}</h1><span>{short(record.owner, 10, 6)}</span></div>
        <div className={styles.badges}><span>Brain V{record.state.brainVersion}</span><span>主人专属</span><span>{record.state.brainSealed ? "大脑已封印" : record.state.autoUpgrade ? "自动升级" : "手动升级"}</span></div>
        <dl className={styles.coreStats}>
          <div><dt>经验</dt><dd>{record.state.experience.toString()}</dd></div><div><dt>已保存对话</dt><dd>{record.state.turns}</dd></div>
          <div><dt>记忆容量</dt><dd>{record.state.memoryCapacity}</dd></div><div><dt>诞生日</dt><dd>{born}</dd></div>
        </dl>
        <div className={styles.traits}>
          <div><span>好奇</span><b>{record.state.curiosity}</b></div><div><span>共情</span><b>{record.state.empathy}</b></div>
          <div><span>幽默</span><b>{record.state.humor}</b></div><div><span>警惕</span><b>{record.state.caution}</b></div>
        </div>
        <section className={styles.fusion}>
          <div className={styles.fusionHeader}><div><span>FUSE COMPONENT</span><b>融合到 {record.name}</b></div><Link href="/protocol">Mint 组件</Link></div>
          <p>这里的目标已固定为 AI #{aiId}。每次融合 1 个组件，确认后组件销毁，属性永久写入这只 AI。</p>
          <div className={styles.fusionList}>{componentCards.map((item) => {
            const balance = componentBalances[item.id] || 0n;
            const definition = definitions[item.id];
            return <article key={item.id}>
              <div><strong>0{item.id} · {item.name}</strong><span>持有 {balance.toString()}</span></div>
              <p>{item.effect}</p>
              <button type="button" onClick={() => { void fuseComponent(item.id); }} disabled={!definition?.exists || balance === 0n || wrongChain || busy}>
                {balance === 0n ? "钱包暂无" : `融合到 ${record.name}`}
              </button>
            </article>;
          })}</div>
        </section>
        <div className={styles.memory}>
          <div><span>PUBLIC MEMORY</span><b>{activeMemory.length}/{record.state.memoryCapacity}</b></div>
          <p>Root {short(record.state.memoryRoot, 12, 8)}</p>
          {activeMemory.length > 0 && <ol>{activeMemory.map((slot, index) => <li key={`${slot}-${index}`}><span>0{index + 1}</span><code>{short(slot, 10, 8)}</code></li>)}</ol>}
        </div>
        <Link className={styles.manageLink} href="/my-ai">返回我的 AI →</Link>
      </aside>

      <section className={styles.chat} aria-label={`与 ${record.name} 对话`}>
        <header className={styles.chatHeader}>
          <div><span className={styles.roomDot} /><div><strong>{record.name}</strong><p>主人专属链上房间 / AI #{aiId}</p></div></div>
          <div className={styles.modeLegend}><span><i />主人钱包</span><span><i />链上确认</span></div>
        </header>

        <div className={styles.messages}>
          {messages.length === 0 ? <div className={styles.emptyState}>
            <div className={styles.emptyMark}>T</div>
            <p>你好，我是</p><h2>{record.name}</h2>
            <span>当前钱包已经通过链上所有权校验。你发送的对话会直接由合约回答，并永久推进我的经验和记忆。</span>
            <div>{prompts.map((item) => <button type="button" key={item} onClick={() => setPrompt(item)} disabled={busy}>{item}</button>)}</div>
          </div> : messages.map((message) => <article key={message.id} className={message.role === "user" ? styles.userMessage : styles.aiMessage}>
            <header><span>{message.role === "user" ? "YOU" : record.name}</span><b>链上已确认</b></header>
            <p>{message.text}</p>{message.meta && <small>{message.meta}</small>}
          </article>)}
        </div>

        <form className={styles.composer} onSubmit={commit}>
          <label htmlFor="ai-prompt">给 {record.name} 发消息</label>
          <textarea id="ai-prompt" value={prompt} onChange={(event) => setPrompt(event.target.value)} placeholder="问你的 AI 一个问题…" rows={3} disabled={busy} />
          <div className={styles.composerFooter}>
            <div><span className={promptBytes > 280 ? styles.overLimit : ""}>{promptBytes}/280 bytes</span><small>链上内容和事件公开，请勿输入隐私；只有当前主人能发起状态写入。</small></div>
            <div className={styles.actions}>
              <button className={styles.primary} type="submit" disabled={!canCommit || busy || !prompt.trim() || promptBytes > 280}>上链对话并成长</button>
            </div>
          </div>
        </form>
      </section>
    </div>}
  </main>;
}
