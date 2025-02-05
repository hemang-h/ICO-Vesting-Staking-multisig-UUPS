# ex1ICOv2 Contract Documentation

## Overview
The ex1ICOv2 contract is a multi-stage ICO (Initial Coin Offering) system deployed on the BNB Chain. It supports token purchases via stablecoins (USDC/USDT) and cross-chain ETH transactions (via a backend custodial system). Key features include:

- Non-overlapping stages with configurable schedules and token prices.
- Role-based access control for managing stages, upgrades, and ETH transaction recording.
- Token release flexibility: Direct transfers if `isTokenReleasable` is enabled, or balance tracking for future claims.
- Price oracles for ETH/BTC conversions using Chainlink aggregators.

## Contracts

| Proxy                 | Implementation   |
|-----------------------|------------------|
|https://testnet.bscscan.com/address/0x79823739fe6991921c5fa8aecded1d1b50be08f3#code|https://testnet.bscscan.com/address/0x2325fdefb40bf1285c4d6c1614b6f07899260cde#code|


## Key Features

| Feature                 | Description |
|-------------------------|-------------|
| Multi-Stage ICO        | Sequential stages with unique start/end times and token prices. |
| Non-Overlapping        | Stages cannot overlap; new stages must start after the previous ends. |
| Cross-Chain ETH Support | ETH purchases recorded via a backend custodial wallet on Ethereum. |
| Role-Based Access      | `OWNER`, `UPGRADER`, `ICO_AUTHORISER`, and `ETH_TXN_RECORDER` roles. |
| Token Release Modes    | Immediate transfer or balance tracking for claim schedules (external contract). |

## Roles

| Role                     | Permissions |
|--------------------------|-------------|
| DEFAULT_ADMIN_ROLE       | Full administrative control (inherited from AccessControl). |
| OWNER_ROLE               | Configure token limits, addresses, and toggle token release mode. |
| UPGRADER_ROLE            | Upgrade the contract (UUPS proxy pattern). |
| ICO_AUTHORISER_ROLE      | Create/update/deactivate ICO stages. |
| ETH_TXN_RECORDER_ROLE    | Record ETH-based purchases from the Ethereum chain. |

## Workflow

### 1. ICO Stage Management

#### Creation:
- Only `ICO_AUTHORISER_ROLE` can create stages.
- Stages are checked for non-overlapping timestamps.
- Emits `ICOStageCreated` event.

#### Update/Deactivation:
- Stages can be updated (timestamps, price) or deactivated by `ICO_AUTHORISER_ROLE`.
- Emits `ICOStageUpdated` on changes.

### 2. Token Purchase

#### A. Stablecoin Purchase (USDC/USDT)
1. User calls `buyWithUSDC` / `buyWithUSDT` with token amount and stage ID.
2. Contract verifies:
   - Active stage (`checkSaleStatus` modifier).
   - Token limits per address/transaction.
   - Transfers stablecoins to `receivingWallet`.
3. If `isTokenReleasable`:
   - Tokens are sent to the buyer immediately.
   - Else, balances are tracked in `UserDepositsPerICOStage` and `HoldersCumulativeBalance`.

#### B. ETH Purchase (Cross-Chain)
1. ETH transaction occurs on Ethereum via a backend custodial contract.
2. Backend calls `purchasedViaEth` on BNB Chain (requires `ETH_TXN_RECORDER_ROLE`).
3. ETH amount and token allocation are recorded.
4. Tokens are released or tracked based on `isTokenReleasable`.

### 3. Token Release
- **Direct Transfer**: Enabled via `isTokenReleasable` (toggle by `OWNER_ROLE`).
- **Claim Schedule**: If disabled, tokens are tracked for future claims via an external contract.

## Key Functions

### Stage Management

| Function              | Description |
|----------------------|-------------|
| `createICOStage()`   | Creates a new ICO stage with start/end times and price. |
| `updateICOStage()`   | Updates stage parameters (timestamps, price). |
| `deactivateICOStage()` | Deactivates a stage (prevents further purchases). |

### Token Purchase

| Function              | Description |
|----------------------|-------------|
| `buyWithUSDC()`      | Purchases tokens with USDC (transfers to `receivingWallet`). |
| `buyWithUSDT()`      | Purchases tokens with USDT. |
| `purchasedViaEth()`  | Backend-only function to record ETH purchases (cross-chain). |

### Price Calculations

| Function                | Description |
|------------------------|-------------|
| `getTokenPriceInETH()` | Returns ETH cost for tokens using Chainlink oracle. |
| `getTokenPriceInBTC()` | Returns BTC cost for tokens using Chainlink oracle. |
| `calculatePrice()`     | Calculates USD value for tokens at a specific stage. |

## Events

| Event               | Description |
|---------------------|-------------|
| `TokensBoughtUSD`   | Emitted on USDC/USDT purchase (includes buyer, amount, stage, USD paid). |
| `TokensBoughtETH`   | Emitted on ETH purchase (includes buyer, ETH amount, stage). |
| `ICOStageCreated`   | Emitted when a new ICO stage is created. |
| `ICOStageUpdated`   | Emitted when an existing stage is updated. |

## Flow Diagram

```plaintext
                   +---------------------+
                   |  ICO_AUTHORISER_ROLE |
                   +---------------------+
                            |
                            v
                    (Create/Update Stage)
                            |
                            v
+---------------+       +----------------+       +-------------------+
| ETH Purchases |       | Stablecoin Buy |       | Stage Management  |
| (Ethereum)    |       | (BNB Chain)    |       | (Non-Overlapping) |
+---------------+       +----------------+       +-------------------+
         |                         |                         |
         |                         |                         |
         v                         v                         v
+-------------------+     +------------------+     +-------------------+
| Backend Records   |     | Transfer USDC/USDT|    | Validate Stage    |
| ETH Transaction   |     | to Receiving Wallet|   | Timestamps        |
+-------------------+     +------------------+     +-------------------+
         |                         |                         |
         v                         v                         v
+-------------------+     +------------------+     +-------------------+
| Call purchasedViaEth() | Update Balances   |     | Emit Stage Events |
| (ETH_TXN_RECORDER) |    | or Release Tokens |    | (Created/Updated) |
+-------------------+     +------------------+     +-------------------+
         |                         |
         |                         |
         v                         v
+-------------------+     +------------------+
| Track ETH Raised  |     | Update Total     |
| & Token Allocation|     | Tokens Sold      |
+-------------------+     +------------------+
```

## Security Notes

- Uses OpenZeppelin’s `ReentrancyGuard` for buy functions.
- Critical operations (upgrades, withdrawals) restricted to roles.
- Price oracles use Chainlink’s decentralized feeds for ETH/BTC conversions.
