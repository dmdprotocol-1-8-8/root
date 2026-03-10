# DMD Protocol — Frequently Asked Questions (FAQ)

## General

**What is DMD Protocol?**
DMD Protocol is a fully immutable, governance-free Bitcoin liquidity and emission protocol on Base (Coinbase's Layer 2). Users lock tBTC to earn DMD tokens through a mechanism called EDAD (Extreme Deflationary Digital Asset Mechanism). To unlock your tBTC, you must burn 100% of the DMD earned from that position — permanently destroying it.

**What does EDAD stand for?**
Extreme Deflationary Digital Asset Mechanism. It's a patent-pending system where every DMD token is backed by locked tBTC, and every redemption permanently burns DMD from circulation, making the supply structurally deflationary over time.

**What network does DMD Protocol run on?**
Base Mainnet (Chain ID: 8453), an Ethereum Layer 2 network built by Coinbase. Transactions are fast and cost fractions of a cent.

**Is DMD Protocol decentralized?**
Yes, completely. There are no admin keys, no governance, no upgrades, no emergency controls, and no multisig. Once deployed, the smart contracts run autonomously and permanently. No person or entity can alter the protocol rules.

**Who created DMD Protocol?**
The DMD Foundation supported the initial development. However, the Foundation does not control the protocol. All monetary rules are immutable and enforced by smart contracts. The Foundation's role is temporary and expected to diminish over time.

**Is DMD Protocol audited?**
The protocol has 160+ automated tests with 100% critical-path coverage. Flash-loan attack simulations, supply invariants, and full burn redemption logic have all been tested and verified. Security rating: A+.

---

## Getting Started

**What do I need to start?**
A Web3 wallet (MetaMask, Coinbase Wallet, or any browser wallet), some ETH on Base for gas fees (~$5–10 worth), and tBTC tokens to lock.

**How do I get tBTC on Base?**
Two main options: (1) Bridge tBTC from Ethereum mainnet using bridge.base.org, or (2) Buy ETH on Base and swap it for tBTC on a DEX like Uniswap or Aerodrome. The tBTC contract on Base is `0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b`.

**What is tBTC?**
tBTC is a decentralized Bitcoin wrapper from Threshold Network. It provides decentralized custody with threshold security and Ethereum-native settlement. DMD Protocol only accepts tBTC — no WBTC, no synthetic derivatives.

**Why only tBTC and not WBTC or other Bitcoin wrappers?**
tBTC is decentralized and trustless. WBTC requires custodians and multi-sig management. DMD Protocol's design demands a single, decentralized reserve asset to minimize counterparty risk.

**Is there a minimum amount to lock?**
There's no protocol-enforced minimum, but a recommended minimum of 0.01 tBTC is practical given gas costs.

---

## Locking tBTC

**How do I lock tBTC?**
Go to the tBTC tab, enter the amount and lock duration (1–60 months), click "Approve tBTC" first, then "Lock tBTC." Confirm both transactions in your wallet.

**How long can I lock for?**
1 to 60 months. The weight multiplier bonus caps at 24 months (1.48×), so locking beyond 24 months earns the same rate but you won't need to re-lock.

**Can I change my lock duration after locking?**
No. Lock duration is permanent once set. Choose carefully. You can use early unlock if you need your tBTC before the lock expires (30-day waiting period applies).

**Can I add more tBTC to an existing lock position?**
No. Each lock creates a separate position with its own ID, duration, weight, and earned DMD. To lock more, create a new position.

**How many positions can I have?**
Up to 100 positions per wallet address.

**What is weight and how is it calculated?**
Weight determines your share of DMD emissions. Formula: `Weight = Amount × (1 + min(lockMonths, 24) × 0.02)`. For example, locking 1 tBTC for 12 months gives weight = 1.24. Higher weight = bigger share of emissions.

**What are the weight multipliers?**

| Duration | Multiplier |
|----------|-----------|
| 1 month | 1.02× |
| 6 months | 1.12× |
| 12 months | 1.24× |
| 18 months | 1.36× |
| 24 months | 1.48× (max) |
| 36–60 months | 1.48× (capped) |

---

## Earning DMD

**How do emissions work?**
DMD is distributed in 7-day epochs. At the end of each epoch, DMD emissions are allocated proportionally based on each user's vested lock weight relative to total system weight.

**Do I earn DMD immediately after locking?**
No. There's a 10-day vesting period for flash loan protection. Days 0–7: warmup (0% weight). Days 7–10: linear vesting (0% → 100%). Day 10+: full weight active.

**What is an epoch?**
A 7-day emission cycle. At the end of each epoch, DMD emissions become available for claiming. Anyone can finalize epochs — it's a permissionless public action.

**What does "Finalize Epochs" do?**
It processes pending epochs and calculates the emission distribution. This is a public action — any user can click it. Until an epoch is finalized, users can't claim DMD from that epoch.

**How do I claim my DMD?**
Go to the Emissions tab, click "Claim All DMD." This claims all your earned DMD from all finalized epochs in a single transaction.

**What is the emission schedule?**
Year 1: 3,600,000 DMD. Emissions decay by 25% annually (Year 2: 2,700,000, Year 3: 2,025,000, etc.). Emissions permanently stop when 14.4M DMD is minted.

**Does depositing more tBTC increase total emissions?**
No. The emission pool is fixed and independent of deposits. More deposits means each user's share decreases. Whales cannot inflate the total supply.

**What happens if no one has vested weight during an epoch?**
The epoch is skipped and those emissions are never distributed. This only affects the first 10 days after launch. Skipped emissions permanently reduce the effective supply.

---

## Redemption & Unlocking tBTC

**How do I get my tBTC back?**
Wait for your lock to expire (or use early unlock), then burn 100% of the DMD earned from that position. Your tBTC is returned in full with zero fees.

**Are there any fees for redemption?**
No. Zero fees, zero slippage, zero penalties. You get 100% of your locked tBTC back. You only pay the Base network gas fee (typically under $0.50).

**What if I sold some of my DMD and don't have enough to redeem?**
You must acquire the required DMD to redeem. Buy it back on a DEX or earn it from other positions. The protocol enforces this rule — there are no exceptions and no governance overrides.

**Can I partially redeem a position?**
No. Redemption is all-or-nothing. You must burn 100% of earned DMD to unlock 100% of tBTC from that position.

**What happens to the DMD I burn?**
It's permanently destroyed. The burned DMD can never be reminted. This is what makes the protocol structurally deflationary — every redemption reduces total circulating supply forever.

**What is early unlock?**
If your lock hasn't expired, you can request early unlock. This immediately removes your weight (you stop earning DMD), starts a 30-day waiting period, and after 30 days you can burn DMD and redeem your tBTC.

**Can I cancel an early unlock request?**
Yes, anytime before you redeem. Cancelling restores your weight and you resume earning DMD.

**What is the 30-day early unlock waiting period?**
It's a mandatory cooldown that cannot be shortened. It exists to maintain protocol security and prevent gaming.

---

## Tokenomics & Supply

**What is the maximum supply of DMD?**
18,000,000 DMD hard cap. Only 14,400,000 (80%) is reachable through emissions. The real circulating supply is variable and permanently deflationary due to burn-to-redeem.

**How is DMD distributed?**

| Allocation | % | Amount |
|-----------|---|--------|
| BTC Mining Emissions | 80% | 14,400,000 |
| Foundation | 10% | 1,800,000 |
| Founders | 5% | 900,000 |
| Developers | 2.5% | 450,000 |
| Contributors | 2.5% | 450,000 |

Non-emission allocations follow the Diamond Vesting Curve (5% at launch + 95% linear over 7 years).

**Can the supply ever increase after burning?**
No. Burned DMD is permanently removed. The supply can only go down, never back up. This is hardcoded and immutable.

**What makes DMD deflationary?**
Every time a user burns DMD to redeem tBTC, that DMD is destroyed forever. Market stress causes more redemptions, accelerating burns. Market optimism causes fewer redemptions, freezing supply. Human behavior becomes the scarcity engine.

**Can anyone mint new DMD outside of emissions?**
No. DMD is minted exclusively through the tBTC locking emission mechanism. No admin, no governance, no contract can create additional DMD.

---

## Security & Technical

**Can the contracts be upgraded or changed?**
No. All contracts are immutable — no proxy contracts, no upgrade paths, no owner privileges. The rules are permanent.

**What about flash loan attacks?**
The protocol has a 10-day weight vesting period (7-day warmup + 3-day linear vest). Flash loans cannot gain immediate weight, making them unprofitable.

**What if there's a bug in the smart contracts?**
Immutability means no fixes post-deployment. However, the protocol has been tested with 160+ automated tests, flash-loan simulations, and supply invariant verification. The trade-off for immutability is certainty — the rules can never change, for better or worse.

**Does DMD Protocol use oracles?**
No. The core protocol has zero oracle dependencies. All calculations are on-chain and deterministic.

**What is the PDC (Protocol Defense Consensus)?**
A minimal voting system that exists only to manage external tBTC adapter integrations. It has zero authority over monetary rules, supply, emissions, or redemptions. It activates only when circulating supply reaches 30% of max (5.4M DMD) AND there are 10,000+ unique holders.

**What can PDC do and not do?**
PDC CAN: pause/resume/approve/deprecate tBTC adapters. PDC CANNOT: change emissions, modify supply, move/freeze BTC, upgrade contracts, or change redemption rules.

**Is my tBTC safe in the vault?**
Your tBTC is held by the immutable BTCReserveVault smart contract. No admin, no governance, and no person has the ability to access, freeze, or move your locked tBTC. Only you can redeem it by burning the required DMD.

---

## Wallet & Technical Issues

**Which wallets are supported?**
MetaMask, Coinbase Wallet, and most browser-based Web3 wallets that support Base network.

**How much gas does it cost?**
Base network gas is very cheap. Approvals: ~$0.10–$0.50. Locks: ~$0.50–$2.00. Claims: ~$0.30–$1.00. Redemptions: ~$0.50–$2.00.

**My transaction failed. What should I do?**
Check that you have enough ETH on Base for gas. Verify you're on the correct network (Base Mainnet, Chain ID 8453). For redemptions, ensure you have sufficient DMD balance. If a transaction is stuck, try increasing gas in your wallet.

**How do I add DMD to my wallet?**
In MetaMask: Assets → Import tokens → enter `0xc41848d1548a16F87C7e61296A8d2Dc6e9cb07E8`. Token name: DMD Protocol, Symbol: DMD, Decimals: 18.

**The dashboard shows "—" or is not loading. What's wrong?**
The app loads data from Base RPC endpoints. If data isn't appearing, try refreshing the page, checking your internet connection, or switching to a different RPC. The app uses SWR caching, so previously loaded data should appear instantly on return visits.

---

## Strategy & Best Practices

**What's a good lock duration for beginners?**
Start with a short lock (1–6 months) using a small test amount (0.01–0.1 tBTC) to understand the process. Once comfortable, consider longer locks for higher weight multipliers.

**Should I create one big position or multiple smaller ones?**
Multiple positions give flexibility — you can redeem them independently. One large position maximizes simplicity. Consider splitting if you want to sell some DMD while keeping enough to redeem specific positions.

**Should I sell my earned DMD?**
Be careful. If you sell all your DMD, you won't be able to redeem your tBTC until you buy it back. Always keep enough DMD to cover your redemption requirements, or plan your exit strategy carefully.

**When is the best time to claim DMD?**
You can claim all epochs in a single transaction, so there's no rush. Some users claim weekly, others accumulate and claim less frequently. Gas costs are minimal either way.

**What happens if I lose access to my wallet?**
Your locked tBTC and earned DMD are tied to your wallet address. If you lose your private key or seed phrase, you lose access permanently. The protocol has no recovery mechanism — self-custody is your responsibility.

---

## Comparisons

**How is DMD different from yield farming?**
Yield farming typically inflates token supply to generate returns. DMD does the opposite — every redemption burns tokens permanently. DMD is not yield farming; it's programmable scarcity.

**How is DMD different from Bitcoin?**
Bitcoin uses mining halvings but has no reserve lock, no burn-to-redeem, and no market-driven deflation loop. DMD combines a Bitcoin-style halving emission schedule with a mandatory burn mechanism that makes the supply permanently decrease.

**How is DMD different from stablecoins?**
Stablecoins aim for price stability at $1. DMD has no price target — it's designed for scarcity. Its supply decreases over time rather than staying stable.

**How is DMD different from WBTC?**
WBTC is a wrapped Bitcoin that requires custodians, allows redemption without burning, and doesn't enforce scarcity. DMD enforces mandatory burning, is fully decentralized, and becomes scarcer with every redemption.

---

## Legal & Disclaimers

**Is DMD Protocol regulated?**
DMD Protocol is fully decentralized software with no admin controls. It is not financial advice. Users should consult their own legal and financial advisors.

**Is the EDAD mechanism patented?**
Yes, a U.S. patent application has been filed for the EDAD mechanism. The open-source code is freely usable; the economic mechanism is protected from unauthorized commercial replication.

**What are the risks?**
Immutability means no bug fixes post-deployment. DMD liquidity depends on market adoption. tBTC is an external and independent system. Smart contract interactions are irreversible. You are solely responsible for all actions. This is not financial advice.

---

## Contract Addresses (Base Mainnet)

| Contract | Address |
|----------|---------|
| BTCReserveVault | `0x4eFDA2509fc24dCCf6Bc82f679463996993B2b4a` |
| EmissionScheduler | `0xB9669c647cC6f753a8a9825F54778f3f172c4017` |
| MintDistributor | `0xcccD12bCb557FCE8a9e23ECFAd178Ecc663058Da` |
| DMDToken | `0xc41848d1548a16F87C7e61296A8d2Dc6e9cb07E8` |
| RedemptionEngine | `0xF86d34387A8bE42e4301C3500C467A57F0358204` |
| VestingContract | `0xFcef2017590A4cF73E457535A4077e606dA2Cd9A` |
| PDC | `0x881752EB314E3E562b411a6EF92f12f0f6B895Ee` |
| tBTC (External) | `0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b` |
