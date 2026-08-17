import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "TinyAI - BSC 链上 AI",
  description: "运行在 BSC 智能合约中的链上 AI。",
  icons: { icon: "/icon.svg" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
