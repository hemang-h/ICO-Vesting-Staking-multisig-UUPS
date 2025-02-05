# ICOVesting Contract Documentation

---

## **Overview**
The **ICOVesting** contract is a linear vesting system designed to allow users who participated in the ICO to claim their tokens over time. The vesting is linear, meaning tokens are released in equal slices over a predefined period. Users can only claim tokens once the claim interval has been reached. The contract integrates with the **ex1ICO** contract to fetch user balances and ICO stage details.

---
## Contracts

| Proxy                 | Implementation   |
|-----------------------|------------------|
|https://testnet.bscscan.com/address/0x6933a9ebf29f3299014e8e5477a23e44e74540f6|https://testnet.bscscan.com/address/0x2387595f9b9ad54c3e59a39b705611b4fc7b9feb#code|

---

## **Key Features**
| Feature               | Description                                                                 |
|-----------------------|-----------------------------------------------------------------------------|
| **Linear Vesting**    | Tokens are released in equal slices over a predefined period.               |
| **Claim Intervals**   | Users can only claim tokens after a specific interval has passed.           |
| **Slice Period**      | Tokens are divided into slices based on a slice period (e.g., seconds).     |
| **Role-Based Access** | `OWNER`, `UPGRADER`, and `VESTING_AUTHORISER` roles for contract management.|
| **Integration with ICO** | Fetches user balances and ICO stage details from the `ex1ICO` contract.  |

---

## **Roles**
| Role                  | Permissions                                                                 |
|-----------------------|-----------------------------------------------------------------------------|
| `DEFAULT_ADMIN_ROLE`  | Full administrative control (inherited from AccessControl).                |
| `OWNER_ROLE`          | Update ICO interface, token address, and manage upgrades.                  |
| `UPGRADER_ROLE`       | Upgrade the contract (UUPS proxy pattern).                                 |
| `VESTING_AUTHORISER_ROLE` | Create and update claim schedules.                                     |

---

## **Workflow**
### **1. Claim Schedule Management**
- **Creation**:  
  - Only `VESTING_AUTHORISER_ROLE` can create claim schedules.  
  - Schedules are tied to specific ICO stages and define the start/end times, interval, and slice period.  
  - Emits `ClaimScheduleCreated` event.  

- **Update**:  
  - Schedules can be updated by `VESTING_AUTHORISER_ROLE`.  
  - Ensures updates do not conflict with active claims.  

### **2. Token Claiming**
1. User calls `claimTokens` with the ICO stage ID.
2. Contract verifies:
   - Claim schedule is active (`startTime` <= current time <= `endTime`).
   - User has tokens to claim (`UserDepositsPerICOStage` > 0).
   - Claim interval has been reached (`block.timestamp - prevClaimTimestamp >= interval`).
3. Calculates the claimable amount using `calculateClaimableAmount`.
4. Transfers tokens to the user and updates claimed balances.
5. Emits `TokensClaimed` event.

### **3. Claimable Amount Calculation**
- Tokens are divided into slices based on the `slicePeriod`.
- The claimable amount is calculated as:
  ```
  tokenPerSlice = totalDeposits / totalNumberOfSlices
  claimableAmount = tokenPerSlice * elapsedSlices - claimedAmount
  ```
- If the current time exceeds the `endTime`, the remaining balance is claimable.

---

## **Key Functions**
### **Claim Schedule Management**
| Function               | Description                                                                 |
|------------------------|-----------------------------------------------------------------------------|
| `setClaimSchedule()`   | Creates a new claim schedule for an ICO stage.                             |
| `updateClaimSchedule()`| Updates an existing claim schedule.                                        |

### **Token Claiming**
| Function               | Description                                                                 |
|------------------------|-----------------------------------------------------------------------------|
| `claimTokens()`        | Allows users to claim their vested tokens.                                 |
| `calculateClaimableAmount()` | Calculates the amount of tokens a user can claim.                  |

### **Utility Functions**
| Function               | Description                                                                 |
|------------------------|-----------------------------------------------------------------------------|
| `nextClaimTime()`      | Returns the next claim time for a user.                                    |
| `getBalanceLeftToClaim()` | Returns the remaining balance of tokens a user can claim.               |

---

## **Events**
| Event                  | Description                                                                 |
|------------------------|-----------------------------------------------------------------------------|
| `ClaimScheduleCreated` | Emitted when a new claim schedule is created.                              |
| `TokensClaimed`        | Emitted when a user claims tokens (includes beneficiary, amount, and stage).|

---

## **Flow Diagram**
```plaintext
                   +---------------------+
                   | VESTING_AUTHORISER  |
                   +---------------------+
                            |
                            v
                    (Create/Update Schedule)
                            |
                            v
+---------------+       +----------------+       +-------------------+
| Claim Schedule|       | Token Claiming |       | Balance Tracking  |
| Management    |       | (Linear Vesting)|      | (User Balances)   |
+---------------+       +----------------+       +-------------------+
         |                         |                         |
         |                         |                         |
         v                         v                         v
+-------------------+     +------------------+     +-------------------+
| Validate Schedule |     | Check Claim      |     | Fetch User        |
| (Start/End Times) |     | Interval & Slice |     | Deposits from ICO |
+-------------------+     +------------------+     +-------------------+
         |                         |                         |
         v                         v                         v
+-------------------+     +------------------+     +-------------------+
| Emit Schedule     |     | Calculate        |     | Update Claimed    |
| Created Event     |     | Claimable Amount |     | Balances          |
+-------------------+     +------------------+     +-------------------+
         |                         |
         |                         |
         v                         v
+-------------------+     +------------------+
| Transfer Tokens   |     | Emit Tokens      |
| to User           |     | Claimed Event    |
+-------------------+     +------------------+
```

---

## **Security Notes**
- Uses OpenZeppelin’s `ReentrancyGuard` to prevent reentrancy attacks during token claims.
- Critical operations (upgrades, schedule updates) restricted to roles.
- Ensures claim schedules do not overlap with active ICO stages.
- Integrates with the `ex1ICO` contract to fetch user balances securely.