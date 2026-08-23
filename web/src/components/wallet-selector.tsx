/* eslint-disable @next/next/no-img-element -- EIP-6963 wallet icons are runtime data URIs supplied by browser extensions. */
"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { EIP1193Provider } from "viem";
import styles from "./wallet-selector.module.css";

const WALLET_STORAGE_KEY = "tinyai.preferred-wallet";

export type InjectedProvider = EIP1193Provider & {
  on?: (event: string, listener: (...args: unknown[]) => void) => void;
  removeListener?: (event: string, listener: (...args: unknown[]) => void) => void;
  providers?: InjectedProvider[];
  isMetaMask?: boolean;
  isPhantom?: boolean;
  isOkxWallet?: boolean;
  isOKExWallet?: boolean;
  isBinance?: boolean;
  isBinanceChain?: boolean;
  isCoinbaseWallet?: boolean;
  isRabby?: boolean;
};

type EIP6963ProviderDetail = {
  info: { uuid: string; name: string; icon: string; rdns: string };
  provider: InjectedProvider;
};

export type WalletOption = {
  id: string;
  name: string;
  rdns: string;
  icon: string;
  provider: InjectedProvider;
  standard: "EIP-6963" | "Legacy";
};

type WalletBrowserWindow = Window & {
  ethereum?: InjectedProvider;
  phantom?: { ethereum?: InjectedProvider };
  okxwallet?: InjectedProvider;
  BinanceChain?: InjectedProvider;
};

declare global {
  interface Window { ethereum?: InjectedProvider }
}

function isProvider(value: unknown): value is InjectedProvider {
  return Boolean(value && typeof (value as InjectedProvider).request === "function");
}

function legacyIdentity(provider: InjectedProvider) {
  if (provider.isOkxWallet || provider.isOKExWallet) return { name: "OKX Wallet", rdns: "com.okex.wallet" };
  if (provider.isPhantom) return { name: "Phantom", rdns: "app.phantom" };
  if (provider.isBinance || provider.isBinanceChain) return { name: "Binance Wallet", rdns: "com.binance.wallet" };
  if (provider.isRabby) return { name: "Rabby Wallet", rdns: "io.rabby" };
  if (provider.isCoinbaseWallet) return { name: "Coinbase Wallet", rdns: "com.coinbase.wallet" };
  if (provider.isMetaMask) return { name: "MetaMask", rdns: "io.metamask" };
  return { name: "Browser Wallet", rdns: "injected.browser-wallet" };
}

function walletRank(name: string) {
  const normalized = name.toLowerCase();
  if (normalized.includes("metamask")) return 1;
  if (normalized.includes("phantom")) return 2;
  if (normalized.includes("okx")) return 3;
  if (normalized.includes("binance")) return 4;
  return 10;
}

function walletFamily(name: string, rdns: string) {
  const identity = `${name || ""} ${rdns || ""}`.toLowerCase();
  if (identity.includes("metamask")) return "metamask";
  if (identity.includes("phantom")) return "phantom";
  if (identity.includes("okx") || identity.includes("okex")) return "okx";
  if (identity.includes("binance")) return "binance";
  if (identity.includes("rabby")) return "rabby";
  if (identity.includes("coinbase")) return "coinbase";
  return (rdns || name || "evm-wallet").toLowerCase();
}

function safeWalletIcon(icon: string | undefined) {
  if (!icon) return null;
  return /^data:image\/(?:svg\+xml|png|webp|jpeg|gif)(?:;|,)/i.test(icon) ? icon : null;
}

function fallbackWalletIcon(name: string, rdns: string) {
  const family = walletFamily(name, rdns);
  if (["metamask", "phantom", "okx", "binance"].includes(family)) return `/wallets/${family}.svg`;
  return "/wallets/evm-wallet.svg";
}

function readPreferredWallet() {
  try { return window.localStorage.getItem(WALLET_STORAGE_KEY); }
  catch { return null; }
}

function rememberPreferredWallet(rdns: string) {
  try { window.localStorage.setItem(WALLET_STORAGE_KEY, rdns); }
  catch { /* Wallet selection still works when storage is unavailable. */ }
}

export function useWalletSelector() {
  const [wallets, setWallets] = useState<WalletOption[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const explicitSelection = useRef<string | null>(null);

  useEffect(() => {
    const found = new Map<string, WalletOption>();
    let legacyIndex = 0;

    const publish = () => {
      const next = [...found.values()].sort((a, b) => walletRank(a.name) - walletRank(b.name) || a.name.localeCompare(b.name));
      setWallets(next);
      setSelectedId(() => {
        const explicit = explicitSelection.current;
        if (explicit && next.some((wallet) => wallet.id === explicit)) return explicit;
        const remembered = readPreferredWallet();
        const rememberedWallet = next.find((wallet) => wallet.rdns === remembered);
        if (rememberedWallet) return rememberedWallet.id;
        return next.length === 1 ? next[0].id : null;
      });
    };

    const add = (wallet: WalletOption) => {
      const duplicate = [...found.values()].find((known) =>
        known.provider === wallet.provider
        || walletFamily(known.name, known.rdns) === walletFamily(wallet.name, wallet.rdns),
      );
      if (duplicate) {
        if (duplicate.standard === "Legacy" && wallet.standard === "EIP-6963") {
          found.delete(duplicate.id);
          found.set(wallet.id, wallet);
          publish();
        }
        return;
      }
      found.set(wallet.id, wallet);
      publish();
    };

    const announce = (rawEvent: Event) => {
      const detail = (rawEvent as CustomEvent<EIP6963ProviderDetail>).detail;
      if (!detail?.info || !isProvider(detail.provider)) return;
      // A standards-based announcement is authoritative. Remove only ambiguous
      // rows inferred from the shared window.ethereum compatibility object.
      for (const id of found.keys()) {
        if (id.startsWith("legacy:shared:")) found.delete(id);
      }
      add({
        id: `eip6963:${detail.info.uuid}`,
        name: detail.info.name || "EVM Wallet",
        rdns: detail.info.rdns || detail.info.name.toLowerCase(),
        icon: safeWalletIcon(detail.info.icon) || fallbackWalletIcon(detail.info.name, detail.info.rdns),
        provider: detail.provider,
        standard: "EIP-6963",
      });
    };

    window.addEventListener("eip6963:announceProvider", announce);
    window.dispatchEvent(new Event("eip6963:requestProvider"));

    const fallbackTimer = window.setTimeout(() => {
      const browserWindow = window as WalletBrowserWindow;
      const addLegacy = (
        candidate: InjectedProvider,
        identity = legacyIdentity(candidate),
        source: "dedicated" | "shared" = "dedicated",
      ) => {
        add({
          id: `legacy:${source}:${identity.rdns}:${legacyIndex++}`,
          name: identity.name,
          rdns: identity.rdns,
          icon: fallbackWalletIcon(identity.name, identity.rdns),
          provider: candidate,
          standard: "Legacy",
        });
      };

      // Dedicated globals are unambiguous enough to keep as a compatibility path.
      // Dedupe makes the EIP-6963 announcement win when the same wallet exposes both.
      if (isProvider(browserWindow.phantom?.ethereum)) {
        addLegacy(browserWindow.phantom.ethereum, { name: "Phantom", rdns: "app.phantom" });
      }
      if (isProvider(browserWindow.okxwallet)) {
        addLegacy(browserWindow.okxwallet, { name: "OKX Wallet", rdns: "com.okex.wallet" });
      }
      if (isProvider(browserWindow.BinanceChain)) {
        addLegacy(browserWindow.BinanceChain, { name: "Binance Wallet", rdns: "com.binance.wallet" });
      }

      // Some wallet compatibility layers deliberately expose isMetaMask. Inspect the
      // shared window.ethereum object only when no standards-based wallet was found;
      // otherwise it creates false MetaMask rows and duplicate OKX/Phantom entries.
      const hasStandardWallet = [...found.values()].some((wallet) => wallet.standard === "EIP-6963");
      if (!hasStandardWallet) {
        const injected = browserWindow.ethereum;
        const candidates = injected?.providers?.length ? injected.providers : injected ? [injected] : [];
        for (const candidate of candidates) addLegacy(candidate, legacyIdentity(candidate), "shared");
      }
      setReady(true);
    }, 180);

    return () => {
      window.clearTimeout(fallbackTimer);
      window.removeEventListener("eip6963:announceProvider", announce);
    };
  }, []);

  const selectedWallet = useMemo(
    () => wallets.find((wallet) => wallet.id === selectedId) || null,
    [selectedId, wallets],
  );

  const selectWallet = useCallback((wallet: WalletOption) => {
    explicitSelection.current = wallet.id;
    setSelectedId(wallet.id);
    rememberPreferredWallet(wallet.rdns);
  }, []);

  return { ready, selectedId, selectedWallet, selectWallet, wallets };
}

type WalletSelectorModalProps = {
  open: boolean;
  ready: boolean;
  wallets: WalletOption[];
  selectedId: string | null;
  connectingId: string | null;
  error?: string;
  onClose: () => void;
  onSelect: (wallet: WalletOption) => void;
};

export function WalletSelectorModal({
  open,
  ready,
  wallets,
  selectedId,
  connectingId,
  error,
  onClose,
  onSelect,
}: WalletSelectorModalProps) {
  const dialog = useRef<HTMLElement>(null);
  const closeButton = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const previousFocus = document.activeElement as HTMLElement | null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButton.current?.focus();
    const handleKeydown = (event: KeyboardEvent) => {
      if (event.key === "Escape") { onClose(); return; }
      if (event.key !== "Tab" || !dialog.current) return;
      const focusable = [...dialog.current.querySelectorAll<HTMLElement>("button:not(:disabled), a[href], [tabindex]:not([tabindex='-1'])")];
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (!first || !last) { event.preventDefault(); return; }
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    window.addEventListener("keydown", handleKeydown);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", handleKeydown);
      previousFocus?.focus();
    };
  }, [onClose, open]);

  if (!open) return null;

  return <div className={styles.overlay} onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <section className={styles.dialog} ref={dialog} role="dialog" aria-modal="true" aria-labelledby="wallet-dialog-title" aria-describedby="wallet-dialog-description">
      <header className={styles.dialogHeader}>
        <div><span>CONNECT WALLET</span><h2 id="wallet-dialog-title">选择你的钱包</h2></div>
        <button className={styles.closeButton} ref={closeButton} type="button" onClick={onClose} aria-label="关闭钱包选择">×</button>
      </header>

      <p className={styles.description} id="wallet-dialog-description">请选择本次使用的钱包。连接只会请求公开地址，不会自动签名、扣款或发送交易。</p>

      <div className={styles.walletList} aria-live="polite">
        {!ready && wallets.length === 0 && <div className={styles.emptyState}><span className={styles.searchPulse} />正在检测浏览器钱包…</div>}
        {ready && wallets.length === 0 && <div className={styles.emptyState}>
          <strong>没有检测到可用的钱包</strong>
          <span>请先安装或启用 EVM 钱包扩展；手机用户可以在钱包自带的 DApp 浏览器中打开本站。</span>
        </div>}
        {wallets.map((wallet) => {
          const connecting = connectingId === wallet.id;
          const selected = selectedId === wallet.id;
          return <button
            className={styles.walletButton}
            type="button"
            key={wallet.id}
            onClick={() => onSelect(wallet)}
            disabled={connectingId !== null}
            aria-current={selected ? "true" : undefined}
          >
            <span className={styles.walletIcon} aria-hidden="true"><img src={wallet.icon} alt="" /></span>
            <span className={styles.walletName}><strong>{wallet.name}</strong><small>{wallet.standard === "EIP-6963" ? "浏览器已检测" : "兼容模式检测"}</small></span>
            <span className={styles.walletAction}>{connecting ? "等待确认…" : selected ? "已选择" : "连接 →"}</span>
          </button>;
        })}
      </div>

      {error && <p className={styles.modalError} role="alert">{error}</p>}

      <footer className={styles.dialogFooter}>
        <span>仅显示当前浏览器实际检测到的钱包</span><b>EIP-6963 / EVM</b>
      </footer>
    </section>
  </div>;
}
