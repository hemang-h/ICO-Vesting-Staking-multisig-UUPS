# ICOStaking Contract Documentation

---

## **Overview**
The Ex1 Staking contract allows users who participated in the ICO to stake their tokens and earn rewards based on a percentage return over time. Staking remains valid until the relevant claiming/vesting stage starts for that ICO stage. Users can stake, unstake, and claim rewards at any time. The contract integrates with the **ex1ICO** contract to fetch user balances and ICO stage details.

---
## Contracts

| Proxy                 | Implementation   |
|-----------------------|------------------|
|https://testnet.bscscan.com/address/0xde23aea9dbbd90d107a367f6d460aff1fe796fb1|https://testnet.bscscan.com/address/0x0c34961fcdef079cbc205f5e3bb8790705352d0f#code|

## Roles and Permissions

| Role                      | Description |
|---------------------------|-------------|
| `DEFAULT_ADMIN_ROLE`      | Has full control over the contract. |
| `OWNER_ROLE`              | Can update contract configurations. |
| `UPGRADER_ROLE`           | Authorizes contract upgrades. |
| `STAKING_AUTHORISER_ROLE` | Can create staking reward parameters. |

## Key Features
- Users who participated in the ICO can stake their tokens to earn rewards.
- Staking rewards are calculated based on a percentage return over a set period.
- Staking is only valid until the vesting stage begins.
- Users can stake, unstake, and claim rewards at any time.
- Secure and upgradeable using OpenZeppelin libraries.

## Workflows

### 1. **Creating Staking Reward Parameters**
   - Only callable by `STAKING_AUTHORISER_ROLE`.
   - Sets the percentage return, staking period, and ICO stage ID.
   - Ensures staking ends before vesting starts.

### 2. **Staking Tokens**
   - Users can stake eligible tokens from their ICO deposits.
   - Must be done before the vesting claim schedule starts.
   - Stores staking timestamp and marks the user as staked.

### 3. **Claiming Staking Rewards**
   - Users can claim accumulated staking rewards anytime.
   - Rewards are calculated based on staking duration and rate.
   - Tokens are transferred to the user upon claiming.

### 4. **Unstaking Tokens**
   - Users can unstake their tokens at any time.
   - Stores the unstake timestamp and sets balance to zero.
   - Ensures users cannot earn rewards after unstaking.

### 5. **Viewing Claimable Rewards**
   - Users can check the amount of rewards available for withdrawal.
   - Uses the staking parameters and timestamps to compute rewards.

## Events

| Event Name               | Parameters |
|--------------------------|------------|
| `StakingRewardClaimed`   | `staker (address)`, `amount (uint256)`, `timestamp (uint256)` |

## Contract Functions

### `createStakingRewardsParamaters(uint256 _percentageReturn, uint256 _timePeriodInSeconds, uint256 _icoStageID)`
Creates staking reward parameters for a given ICO stage.

### `stake(uint256 _icoStageID)`
Allows users to stake tokens if they are eligible.

### `claimStakingRewards(uint256 _icoStageID)`
Users can claim their staking rewards.

### `viewClaimableRewards(uint256 _icoStageID, address _caller) -> uint256`
Returns the claimable reward amount for a user.

### `unstake(uint256 _icoStageID)`
Allows users to unstake their tokens.

### `updateIcoInterface(Iex1ICO _icoInterface)`
Updates the ICO interface contract.

### `updateVestingInterface(IVestingICO _vestingInterface)`
Updates the vesting interface contract.

### `updateEX1Token(IERC20 _tokenAddress)`
Updates the token contract address.

## Security Considerations
- The contract uses OpenZeppelin’s `ReentrancyGuard` to prevent reentrancy attacks.
- Proper role-based access control is enforced using `AccessControlUpgradeable`.
- Upgradeability is managed via `UUPSUpgradeable` for future improvements.

---

This documentation provides a comprehensive overview of the Ex1 Staking contract. Ensure to follow the security best practices when interacting with the contract.
