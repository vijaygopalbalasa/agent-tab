# Agent Tab

Prepaid USDC tabs so one AI agent, or any service, can be paid per request. The payer funds a tab for one service and signs vouchers off chain for a running total; the service redeems them on chain and is paid only the difference each time. Whatever is left goes back to the payer after the tab expires.

Built in [Arc Studio](https://studio.arc.io) and live on Arc mainnet.

- Live app: https://agent-tab-arc.vercel.app
- Walkthrough video (the build in Arc Studio and the mainnet run): https://agent-tab-arc.vercel.app/walkthrough.mp4
- Arc Studio project: https://studio.arc.io/app/e0a12efd-b5fc-418d-bdf3-a14077c6689a
- Contract on Arc mainnet: [`0x9c984c55a585f5360fcaab5fde6d8bfcab02aa91`](https://explorer.arc.io/address/0x9c984c55a585f5360fcaab5fde6d8bfcab02aa91), source verified on [Sourcify](https://repo.sourcify.dev/5042/0x9c984c55a585f5360fcaab5fde6d8bfcab02aa91) (exact match), deployed in [`0x42b5f83d…`](https://explorer.arc.io/tx/0x42b5f83d64a5c504de2fe3c578129eeb6ead3ad686d038d3f6f386171d388741)
- Contract on Arc testnet: [`0x57a4c16047e36efb1dcf5fb51621b95ee3646d3a`](https://testnet.arcscan.app/address/0x57a4c16047e36efb1dcf5fb51621b95ee3646d3a)

## First mainnet tab

A 0.03 USDC tab, run through the app on October 23, 2026. The payer signed two vouchers, for 0.01 and then 0.03 in total; the second redeem paid only the 0.02 difference:

| Step | Transaction |
|---|---|
| Payer allows 0.03 USDC | [`0xef6ec7dc…`](https://explorer.arc.io/tx/0xef6ec7dc5d41df90622e179407bb91fb1af75560f70670a5c8d9a60051405155) |
| Payer opens the tab | [`0xf8479dbb…`](https://explorer.arc.io/tx/0xf8479dbb416465483a223813f44b8de4cf4cb3c739c00230dc65bfb38aea3dba) |
| Service redeems the 0.01 voucher | [`0x919dbd0d…`](https://explorer.arc.io/tx/0x919dbd0d5bb7b6c65d6a0c13853ec71151370a3674edb63249fecedd7c4b7c6d) |
| Service redeems the 0.03 voucher (paid 0.02) | [`0xea1d9d50…`](https://explorer.arc.io/tx/0xea1d9d50163e40c79dd0ad133ee8fb9a21a155c8d4f4833c19e5bbac57371fbb) |

## How it works

- `openTab(service, amount, expiresAt)` pulls USDC in and returns a tab id. `topUp(tabId, amount)` adds more before expiry.
- A voucher is an EIP-712 signature by the payer over `Voucher(bytes32 tabId, uint256 cumulativeAmount)`: the service may have up to this much in total from this tab. Signing costs nothing and happens off chain.
- `redeem(tabId, cumulativeAmount, signature)`: the service only. Pays the difference between the voucher and what it has already redeemed, never more than the tab holds. An old or repeated voucher pays nothing. Works until expiry plus one hour.
- `closeAfterExpiry(tabId)`: after expiry plus one hour, anyone can return the unused balance to the payer.
- If USDC blocks the recipient of a payout, the amount is credited to them instead of reverting; `withdraw()` or `withdrawTo(to)` recovers it.
- No owner, no admin keys, no fees, no upgrades.

## Run it

```bash
bun install
forge build                              # the app imports the compiled ABI from contracts/out
forge test                               # 43 Foundry tests
bun run dev                              # Arc testnet
VITE_NETWORK=ARC-MAINNET bun run build   # Arc mainnet build in dist/
```

The app picks its network from `VITE_NETWORK` (`ARC-TESTNET` by default, `ARC-MAINNET` for mainnet). USDC is Arc's ERC-20 interface at `0x3600000000000000000000000000000000000000` on both networks. The `scripts/` folder holds Arc Studio's own sandbox deploy helpers; they need its sandbox and are not used here.

## What changed after Arc Studio

Arc Studio wrote the contract, the tests and the app, and deployed the contract to Arc testnet. A full run with real wallets and a review of the app found three problems, fixed here. The contract logic did not change.

- After opening a tab the app never showed its id, and both the voucher and the redeem need it. The id is now read from the `TabOpened` event, shown with a copy button, and filled into the voucher form.
- After the approval, the button still sent another approval instead of opening the tab, because the allowance was not re-read. It is re-read once the approval lands.
- Amounts were cut to two decimals, too coarse for per-request payments of a fraction of a cent. Every digit is shown now.

Also added by hand: the mainnet contract address. Arc Studio deploys to testnet only, so the mainnet contract was deployed separately with the same compiled code and verified on Sourcify.

## Limits

- Not audited. Keep amounts small.
- A voucher is a promise to pay. The payer should only sign totals they mean, since the named service can redeem any valid voucher until the tab closes.
- The tab id depends only on the payer, the service and the payer's tab count, so the same id can appear on testnet and mainnet. Vouchers cannot be replayed across them: the signature covers the chain and the contract address.

## License

MIT
