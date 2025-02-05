# eX1 Token Contract Documentation

## Overview
The eX1 Token is an ERC20-compliant smart contract with multi-signature functionality for restricted addresses. Key features include:

- Standard ERC20 token operations
- Multi-signature approval system for transfers from restricted addresses
- Upgradeable contract architecture (UUPS pattern)
- Role-based access control (DEFAULT_ADMIN, OWNER, APPROVER, EXECUTOR)

## Contracts

| Proxy                 | Implementation   |
|-----------------------|------------------|
|                       |                  |

## Roles and Permissions

| Role                  | Description |
|-----------------------|-------------|
| DEFAULT_ADMIN_ROLE   | Manages fundamental contract settings and approver status updates |
| OWNER_ROLE           | Manages restricted addresses list |
| APPROVER_ROLE        | Approves/rejects proposed transfers from restricted addresses |
| EXECUTOR_ROLE        | Can manually execute approved transfers (with DEFAULT_ADMIN) |

## Key Functionality

### 1. Transfer Workflows

#### Normal Address Transfer (Non-Restricted)

```mermaid
graph TD
    A[User calls transfer(to, value)] --> B{Is sender restricted?}
    B -->|No| C[Execute transfer immediately]
    C --> D[Update balances]
```

#### Restricted Address Transfer

```mermaid
graph TD
    A[Restricted User calls transfer(to, value)] --> B{Is sender restricted?}
    B -->|Yes| C[Create Transfer Proposal]
    C --> D[Emit TransferProposed event]
    D --> E[Approvers review proposal]
    E --> F{Approvals >= Required?}
    F -->|Yes| G[Execute transfer automatically]
    F -->|No| H[Wait for more approvals]
```

### 2. Core Functions

#### `transfer(address _to, uint256 _value)`
- Overridden ERC20 transfer function
- **Special Behavior**: Creates proposal if sender is restricted

#### `approveTransfer(uint256 _txIndex)`
- Allows `APPROVER_ROLE` to approve a proposal
- Automatically executes transfer when approval threshold met

#### `revokeApproval(uint256 _txIndex)`
- Allows `APPROVER_ROLE` to revoke previous approval

#### `executeTransfer(uint256 _txIndex)`
- Manual execution path (requires `DEFAULT_ADMIN` + `EXECUTOR` roles)

### 3. Administration Functions

| Function                  | Description                           | Required Role |
|---------------------------|-------------------------------------|---------------|
| `addRestrictedAddress`   | Adds address to restricted list     | OWNER_ROLE    |
| `removeRestrictedAddress`| Removes address from restricted list | OWNER_ROLE    |
| `updateApprovers`        | Enables/disables approvers          | DEFAULT_ADMIN_ROLE |

## Events

| Event               | Description                             | Parameters |
|---------------------|-------------------------------------|------------|
| `TransferProposed` | New transfer proposal created       | txIndex, proposer, recipient, value |
| `TransferApproved` | Approver voted for proposal        | txIndex, approver |
| `TransferExecuted` | Transfer successfully executed     | txIndex |
| `ApprovalRevoked`  | Approver revoked their vote        | txIndex, approver |

## Upgradeability

- Uses UUPS upgrade pattern
- Upgrades authorized by `DEFAULT_ADMIN_ROLE` via `_authorizeUpgrade`
- Initial contract setup through `initialize` function

## Security Features

- Initialization lock via `_disableInitializers`
- `EnumerableSet` for efficient restricted address management
- Unique approver validation during initialization
- Proposal state checks (`txExists`, `notExecuted`, `notApproved` modifiers)
- Role-based access control for all sensitive operations

## Important Storage Structures

```solidity
struct Transaction {
    address from;
    address to;
    uint256 value;
    bool executed;
    uint256 approvalCount;
}

// Storage Mappings
mapping(uint256 => mapping(address => bool)) public approved;
mapping(address => bool) public isApprover;
```

## Usage Example

### Creating a Proposal
1. Restricted address calls `transfer(recipient, 1000)`
2. Contract creates proposal and returns `txIndex`
3. Emits `TransferProposed` event

### Approving a Transfer
1. Approver calls `approveTransfer(txIndex)`
2. Contract verifies approver status and proposal state
3. If approval threshold reached:
   - Executes transfer
   - Emits `TransferExecuted`

### Typical Workflow

#### Restricted Transfer Flow:
```
Propose → [Approve × N] → Execute → Transfer Complete
```

#### Normal Transfer Flow:
```
Propose → Immediate Execution