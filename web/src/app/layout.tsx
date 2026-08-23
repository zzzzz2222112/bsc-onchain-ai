import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "TinyAI - BSC 链上 AI",
  description: "TinyAI Protocol：以 TINYAI 结算、由 BSC 智能合约执行的可拥有链上 AI。",
  metadataBase: new URL("https://bnbtinyai.org"),
  icons: { icon: "/tinyai-avatar.png", apple: "/tinyai-avatar.png" },
  openGraph: {
    title: "TinyAI Protocol",
    description: "Sovereign on-chain AI state machines for the EVM.",
    images: ["/tinyai-avatar.png"],
    siteName: "TinyAI Protocol",
    type: "website",
  },
  twitter: {
    card: "summary",
    title: "TinyAI Protocol",
    description: "Sovereign on-chain AI state machines for the EVM.",
    images: ["/tinyai-avatar.png"],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
