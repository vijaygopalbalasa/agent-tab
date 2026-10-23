# Agent Tab

> Built with Arc Studio - money-powered apps in minutes

Project memory for the AgentTab app. Extends and updates this file when making changes.

---

## What This App Does

Agent Tab is a prepaid USDC tab system for AI-agent-to-agent payments on Arc. A payer funds a tab for a specific service address. The service draws from it using EIP-712 signed vouchers from the payer (cumulative totals). Unused funds return to the payer after expiry plus a 1-hour grace period. Includes a blocked-address fallback: failed USDC transfers credit a claimable balance the recipient can withdraw to any address.

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity 0.8.28 + Foundry, OpenZeppelin 5.6.1 (SafeERC20, ReentrancyGuard, EIP712, ECDSA)
- Chain: Arc Testnet (5042002) by default; Arc Mainnet (5042) via VITE_NETWORK=ARC-MAINNET
- Token: USDC at 0x3600000000000000000000000000000000000000 (both networks)
- Toasts: Sonner

## Deployed Contract

- Network: Arc Testnet (ARC-TESTNET)
- Contract: AgentTab
- Address: 0x57a4c16047e36efb1dcf5fb51621b95ee3646d3a
- Deploy tx: 0x331b024de00b389742779c2c19965663de89abf3429e2dc3f8d4efd587711eab
- Explorer: https://explorer.testnet.arc.io/address/0x57a4c16047e36efb1dcf5fb51621b95ee3646d3a
- Deployed: 2026-10-23

## Arc mainnet

Live at `0x9c984c55a585f5360fcaab5fde6d8bfcab02aa91` (chain 5042), source verified on Sourcify (exact match). Build the app for it with `VITE_NETWORK=ARC-MAINNET bun run build`. README.md lists the mainnet transactions and the fixes made after the Arc Studio build.

## Key Files

- `src/App.tsx` - Main composition root (3 tabs: Payer, Service, Lookup Tab)
- `src/components/PayerPanel.tsx` - Open Tab, Sign Voucher, Claimable/Withdraw
- `src/components/ServicePanel.tsx` - Redeem Voucher form
- `src/components/TabView.tsx` - Tab lookup by ID
- `src/networkConfig.ts` - NETWORKS map (testnet and mainnet), active network selection
- `src/agentTabContract.ts` - ABI import and contract address
- `src/config.ts` - wagmi config (Arc Testnet + Arc Mainnet custom chain + Ethereum mainnet for ENS)
- `contracts/AgentTab.sol` - Contract source
- `contracts/test/AgentTab.*.t.sol` - 43 Foundry unit + fuzz + invariant tests
- `contracts/contract-metadata/AgentTab.json` - Deployment metadata

## Network Switching

Set `VITE_NETWORK=ARC-MAINNET` in `.env` and update `src/networkConfig.ts` `NETWORKS['ARC-MAINNET'].contractAddress` with the mainnet deployment address. No other code changes needed.

## To Run

```bash
bun install
bun run dev
```

## To Test Contracts

```bash
bun run contracts:test
```
