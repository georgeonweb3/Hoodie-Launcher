# Hoodie Launcher Launcher

A token launcher launcher for [$HOODIE](https://robinhoodchain.blockscout.com/token/0xC72c01AAB5f5678dc1d6f5C6d2B417d91D402Ba3) on Robinhood Chain. Every token deployed through it is atomically launched paired with $HOODIE, with liquidity seeded and LP tokens burned to `0xdead` in the same transaction. No owner, no mint function, nothing to rug.

Built for [@0FJAKE](https://twitter.com/0FJAKE)'s $1,000 bounty.

## How it works

1. **`LauncherFactory`** — deploys `TokenLauncher` instances with the $HOODIE address baked in immutably.
2. **`TokenLauncher`** — on `launchToken(name, symbol, supply, hoodieAmount)`, it atomically:
   - Deploys a fresh `LaunchedToken` (fixed supply, no owner, no mint, no blacklist)
   - Deploys a `HoodiePair` (constant-product AMM, x*y=k, 0.3% fee)
   - Seeds the pair with the new token + your $HOODIE
   - Burns `lpBurnBps` of the resulting LP (up to 100%) to `0xdead`
3. **`HoodiePair`** — a self-contained constant-product AMM. Built from scratch instead of using Uniswap v4, to avoid the nonstandard Universal Router calldata risk on Robinhood Chain mainnet.

## Live on mainnet

- **Factory:** [`0xAbC167cf01Bc5b5ad84817C14aD16D13335876C5`](https://robinhoodchain.blockscout.com/address/0xAbC167cf01Bc5b5ad84817C14aD16D13335876C5)
- **Example launcher instance:** `0x60e9b64a0b9a34323ee9d46c6817ef116dc7c853` (feeBps=0, lpBurnBps=10000 / 100%)
- **Proof-of-life token — "Proof of Hood" (POH):** `0x3860d2aa1dbe1171b528da290d134df94f8d0115`
- **HoodiePair (POH/HOODIE):** `0x57d442079eb5b7be8c93e40ef4e86485f04ba9f1`
- **Launch transaction:** [`0x4584d5157d5bd126cb966b568aea85f684977caefd0b057ed431afa3f51ce25f`](https://robinhoodchain.blockscout.com/tx/0x4584d5157d5bd126cb966b568aea85f684977caefd0b057ed431afa3f51ce25f) — `Success`, LP burned to `0xdead` in the same tx.

Robinhood Mainnet — chainId `4663`, RPC `https://rpc.mainnet.chain.robinhood.com`.

## Testnet rehearsal

Before going live, the full flow was rehearsed on Robinhood Chain testnet (chainId `46630`) using a TSLA-pointed test factory, since $HOODIE has no testnet balance. Confirmed 100% LP burn to `0xdead` worked as designed before deploying to mainnet.

## Development

Built with [Foundry](https://getfoundry.sh).

```bash
forge build
forge script script/Deploy.s.sol --rpc-url robinhood_mainnet --broadcast --verify
```

`HOODIE_ADDRESS` and `PRIVATE_KEY` are expected as environment variables at deploy time.

## Notes

- POH is not currently listed on any DEX frontend — the `HoodiePair` contract is custom, so swaps require calling it directly rather than through a standard router UI. A minimal frontend for this is a possible next step.
- Contract source verification on Blockscout is still pending.
