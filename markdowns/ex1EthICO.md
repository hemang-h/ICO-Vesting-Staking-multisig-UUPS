# ETH ICO Smart Contract Documentation

## Overview
The ETH ICO smart contract is designed to facilitate the purchase of tokens using Ethereum (ETH) on the Ethereum blockchain. Since the project cannot accept ETH payments directly on the Binance Smart Chain (BNB Chain), this contract records transactions on the Ethereum blockchain and triggers corresponding transactions on the BNB Chain ICO smart contract. At the time of token release, users receive their tokens on the BNB Chain.

---
## Contracts

| Proxy                 | Implementation   |
|-----------------------|------------------|
|https://sepolia.etherscan.io/address/0x30e52031898f5cf6b1b92abbc867cb226b83077e|https://sepolia.etherscan.io/address/0x536e1ecf37ffa49c701460503b4a0008044d55af#code|

---

## Key Features
- **ETH Payment Recording**: Records ETH transactions on the Ethereum blockchain.
- **BNB Chain Integration**: Triggers corresponding transactions on the BNB Chain ICO smart contract.
- **Token Release**: Users receive tokens on the BNB Chain upon release.
- **ICO Stages**: Supports multiple ICO stages with different start/end times, token prices, and active statuses.
- **Access Control**: Utilizes OpenZeppelin's AccessControl for role-based permissions.
- **Price Oracle Integration**: Uses Chainlink's price oracle to fetch the latest ETH price in USD.

## Contract Details
- **Contract Name**: `Ex1ICO`



## Roles
The contract uses role-based access control to manage permissions. Below is a table of roles and their permissions:

| Role Name | Description |
|-----------|-------------|
| `DEFAULT_ADMIN_ROLE` | Has full administrative privileges, including granting and revoking roles. |
| `OWNER_ROLE` | Can set wallet addresses, token limits, and update the price oracle. |
| `UPGRADER_ROLE` | Can upgrade the contract to a new implementation. |
| `ICO_AUTHORISER_ROLE` | Can create and update ICO stages. |

## Events
The contract emits the following events to track important actions:

| Event Name | Description |
|------------|-------------|
| `TokensBoughtETH` | Emitted when tokens are purchased using ETH. |
| `ICOStageCreated` | Emitted when a new ICO stage is created. |
| `ICOStageUpdated` | Emitted when an existing ICO stage is updated. |

## Key Functions
### `initialize()`
Initializes the contract, setting up roles, initial parameters, and the ETH price oracle.
```solidity
function initialize() public initializer;
```

### `createICOStage()`
Creates a new ICO stage with specified start/end times, token price, and active status.
```solidity
function createICOStage(
    uint256 _startTime
