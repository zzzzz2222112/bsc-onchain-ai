# TinyAI Reference Client

This Next.js application is a replaceable client for TinyAI Protocol. It reads public protocol state, discovers wallet-owned AIs, prepares owner-authorized conversations, exposes component fusion and provides a non-custodial market interface.

The client is not part of the protocol trust boundary. Ownership, inference, brain integrity, memory updates, component effects and market settlement are enforced by contracts.

## Configuration

```bash
cp .env.example .env.local
pnpm install
pnpm lint
pnpm exec tsc --noEmit
pnpm build
pnpm dev
```

`ALCHEMY_API_KEY` is server-only. Never expose it through a `NEXT_PUBLIC_` variable, committed file or wallet-facing RPC URL.

Public configuration includes chain ID, canonical contract addresses, deployment start block, explorer URL and repository URL.

## RPC boundary

`/api/rpc` is a read-only transport with method, contract-address, request-size, batch, calldata, log-range, timeout and rate limits. It cannot broadcast transactions.

Wallet writes go directly through the injected EIP-1193 provider after account, chain, ownership and contract-state checks.

## Owner-only AI rooms

The client enumerates `tokensOfOwner(wallet)` and routes each token to its own room. A room may display public state, but only the current ERC-721 owner can submit `chatAI`, upgrade, seal or fuse.

This is also enforced by `TinyAIProtocol`; client routing is only an earlier user-facing check.

## Market

AI and component listings remain in the seller's wallet until purchase. Approval, listing, purchase, cancellation and seller withdrawal are distinct wallet transactions.

The interface reads live listing state and does not represent listing visibility as guaranteed liquidity.
