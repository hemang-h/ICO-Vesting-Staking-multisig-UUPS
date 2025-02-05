# PrivateVesting Smart Contract Documentation

## Overview

The `PrivateVesting` contract is designed to manage token vesting schedules with role-based access control. Unlike standard ICO vesting, this contract is specifically for addresses that do not participate in the ICO.

---
## Contracts

| Proxy                 | Implementation   |
|-----------------------|------------------|
|https://testnet.bscscan.com/address/0xd3aa046b8147e5f493412c2a620b409d797ac677|https://testnet.bscscan.com/address/0xa10953e1849017f0093898d1774673664782bfb1#code|

---

## Features
- Role-based access control using OpenZeppelin's `AccessControlUpgradeable`.
- Supports token vesting schedules with configurable parameters.
- Allows beneficiaries to claim vested tokens periodically.
- Enables updating, revoking, and managing vesting schedules.
- Utilizes upgradeable contract patterns with `UUPSUpgradeable`.

---

## Contract Roles
- **DEFAULT_ADMIN_ROLE**: The admin with full control.
- **OWNER_ROLE**: Has permissions to revoke vesting schedules.
- **VESTING_CREATOR_ROLE**: Can create and update vesting schedules.
- **UPGRADER_ROLE**: Can upgrade the contract implementation.
---
## Data Structures

### `VestingSchedule` Struct
| Parameter | Type | Description |
|-----------|------|-------------|
| `beneficiary` | `address` | Address of the beneficiary receiving the tokens. |
| `vestingScheduleID` | `uint256` | Unique identifier for the vesting schedule. |
| `totalAmount` | `uint256` | Total number of tokens to be vested. |
| `startTime` | `uint256` | Timestamp when vesting begins. |
| `endTime` | `uint256` | Timestamp when vesting ends. |
| `claimInterval` | `uint256` | Time interval between claims. |
| `cliffPeriod` | `uint256` | Period before tokens start vesting. |
| `slicePeriod` | `uint256` | Time period for vesting calculation. |
| `releasedAmount` | `uint256` | Amount of tokens already claimed. |
| `isRevocable` | `bool` | Whether the vesting schedule can be revoked. |
| `isRevoked` | `bool` | Whether the vesting has been revoked. |

---

## State Variables
- `IERC20 public ex1Token` → Token contract used for vesting.
- `mapping(uint256 => VestingSchedule) public vestingSchedules` → Stores vesting schedules by ID.
- `mapping(uint256 => uint256) public lastClaimedTimestamp` → Tracks the last claim time.
- `mapping(uint256 => mapping(address => uint256)) lastClaimedAmount` → Stores last claimed amounts.
- `mapping(address => uint256[]) public beneficiarySchedules` → Maps beneficiaries to their vesting schedules.
- `uint256 public latestVestingScheduleID` → Tracks the latest vesting schedule ID.
- `uint256[] public scheduleIDs` → List of all vesting schedule IDs.

---

## Events
- `VestingScheduleCreated(address beneficiary, uint256 vestingScheduleID, uint256 totalAmount, uint256 startTime, uint256 endTime, uint256 claimInterval, uint256 cliffPeriod, uint256 slicePeriod, uint256 releasedAmount, bool isRevocable, bool isRevoked)`
- `VestingScheduleRevoked(uint256 vestingScheduleID, uint256 timestamp)`
- `TokensClaimed(address beneficiary, uint256 amount, uint256 timestamp)`

---

## Functions

### `initialize()`
- Initializes the contract with roles and token contract address.

### `setVestingSchedule()`
- Creates a new vesting schedule with the specified parameters.

### `updateVesting()`
- Updates an existing vesting schedule if modifications are needed.

### `claimTokens()`
- Allows beneficiaries to claim vested tokens based on eligibility.

### `calculateClaimableAmount()`
- Computes the amount of tokens that can be claimed at the current time.

### `revokeSchedule()`
- Revokes a vesting schedule if it was marked as revocable.

### `nextClaimTime()`
- Returns the timestamp of the next eligible claim.

### `getBalanceLeftToClaim()`
- Fetches the remaining balance of vested tokens.

### `getAllVestingSchedules()`
- Returns all vesting schedules stored in the contract.

### `getBeneficiarySchedules()`
- Retrieves the vesting schedule IDs for a given beneficiary.

### `setEx1TokenSaleContract()`
- Updates the ERC20 token address used for vesting.

### `_authorizeUpgrade()`
- Ensures only the upgrader role can update the contract implementation.

---

## Security Considerations
- The contract follows best practices to prevent reentrancy and unauthorized modifications.
- Only assigned roles can modify or revoke schedules.
- Tokens are transferred securely using OpenZeppelin’s `SafeERC20` library.

---

## Usage
This contract is ideal for private token allocations that do not follow the ICO vesting process, allowing flexibility in token distribution while maintaining security and transparency.

---
