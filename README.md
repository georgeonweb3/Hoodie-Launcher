# HOODIE Launcher Launcher

Built for Hoodie Jake's bounty: a token launcher launcher on Robinhood Chain
where every token launched through every launcher must be paired with
$HOODIE — permanently, by construction, not by policy.

## How it works

```
LauncherFactory (the "launcher launcher")
  └─ createLauncher(...) deploys →  TokenLauncher (a launcher)
                                        └─ launchToken(...) deploys →  LaunchedToken (ERC20)
                                                                    +  HoodiePair (HOODIE ⇄ token pool)
```

- `hoodie` is set once, in the constructor, at every level (`LauncherFactory`
  → `TokenLauncher` → `HoodiePair`), and is `immutable`. There is no setter
  anywhere in this repo. A launcher physically cannot be reconfigured to
  pair with anything else.
- `launchToken()` mints the new token and seeds the HOODIE pool in the same
  transaction. There's no second step where a creator could launch the
  token and skip the pairing.
- `HoodiePair` is a small self-contained constant-product AMM (not a
  Uniswap fork/integration) — see the note in `src/HoodiePair.sol` for why.

## Anti-rug features (already built in)

- **LP burn on launch** — each `TokenLauncher` has a fixed `lpBurnBps` set
  at deployment. A launcher configured with `lpBurnBps = 10_000` burns
  100% of LP on every launch made through it, so liquidity can never be
  pulled by anyone, ever, for any token launched there.
- **Minimum liquidity lock** — every pool permanently locks 1000 units of
  LP to `0x...dead` on first mint (same mechanism Uniswap v2 uses), so a
  pool can never be drained to a zero/undefined price.
- **Immutable fee cap** — `TokenLauncher` hard-caps its own fee at 10% of
  the HOODIE side, enforced in the constructor, regardless of what a
  launcher creator tries to configure.
- **No admin keys** — no owner, no pausability, no upgradability anywhere
  in the three contracts. What's deployed is what runs.

## Setup (Termux)

```bash
pkg install git curl -y
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup

cd hoodie-launcher-launcher
forge install OpenZeppelin/openzeppelin-contracts foundry-rs/forge-std --no-commit
```

## Deploy to testnet first

```bash
export HOODIE_ADDRESS=0xC72c01AAB5f5678dc1d6f5C6d2B417d91D402Ba3   # confirm on mainnet — see note below
export PRIVATE_KEY=0x<your_testnet_key>

forge script script/Deploy.s.sol --rpc-url robinhood_testnet --broadcast
```

Then do one full end-to-end launch against testnet (create a launcher,
launch a token through it, confirm the pool has both assets and LP got
burned/sent correctly) before touching mainnet. This isn't "mock testing" —
it's the one live rehearsal you want before spending real gas and real
$HOODIE on the bounty submission itself.

## Deploy to mainnet

```bash
export HOODIE_ADDRESS=0xC72c01AAB5f5678dc1d6f5C6d2B417d91D402Ba3
export PRIVATE_KEY=0x<your_mainnet_key>

forge script script/Deploy.s.sol --rpc-url robinhood_mainnet --broadcast
```

**Before you run this**, double check `HOODIE_ADDRESS` against the CA in
Hoodie Jake's tweet yourself, digit by digit, from the source — I
transcribed it from a screenshot and screenshots are exactly how people
get rugged by a one-character-off contract address. Don't trust my copy of
it, verify it on the block explorer.

## Verify on Blockscout

```bash
forge verify-contract <FACTORY_ADDRESS> \
  src/LauncherFactory.sol:LauncherFactory \
  --chain-id 4663 \
  --rpc-url robinhood_mainnet \
  --verifier blockscout \
  --verifier-url https://robinhoodchain.blockscout.com/api \
  --constructor-args $(cast abi-encode "constructor(address)" $HOODIE_ADDRESS)
```

Verified source is close to free points on a bounty like this — judges can
read exactly what they're voting for without trusting a claim.

## What would make this submission stronger (your call on time budget)

1. **Run the full flow on mainnet before the deadline**, not just testnet —
   create at least one real launcher and one real token through it, so
   your submission links to something live and working, not just verified
   code sitting idle.
2. **One-page static frontend** (plain HTML + ethers.js via CDN, no build
   step) with a "Create Launcher" form and a "Launch Token" form. Doesn't
   need to be pretty — a working form beats a polished screenshot for a
   dev-audience bounty. Can host on GitHub Pages straight from Termux.
3. **Short demo clip** (screen recording of an actual launch transaction
   going through, then the resulting pool visible on the explorer) —
   Hoodie Jake's post explicitly says "link to enter," and a 30-second
   proof-of-life clip is the highest-signal thing you can attach.
4. **Quote-tweet with the launcher's deployed address and one launched
   token as a live example** — gives judges something to click into
   immediately instead of having to read code first.

Everything above is additive — the contracts are complete and deployable
as they are. Do 1 and 3 if you only have time for two things; they're what
turn "audited code" into "obviously working."
