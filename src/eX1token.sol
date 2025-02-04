// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title EX1
 * @dev A multi-signature ERC20 token contract with upgradeable functionality.
 * This contract allows for proposing, approving, and executing transfers, with restrictions on certain addresses.
 */
contract EX1 is Initializable, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");

    /**
     * @dev Struct representing a proposed transaction.
     * @param from The address initiating the transfer.
     * @param to The address receiving the tokens.
     * @param value The amount of tokens to transfer.
     * @param executed Whether the transaction has been executed.
     * @param approvalCount The number of approvals the transaction has received.
     */
    struct Transaction {
        address from;
        address to;
        uint256 value;
        bool executed;
        uint256 approvalCount;
    }

    event TransferProposed(uint256 indexed txIndex, address indexed proposer, address indexed to, uint256 value);
    event TransferApproved(uint256 indexed txIndex, address indexed approver);
    event TransferExecuted(uint256 indexed txIndex);
    event ApprovalRevoked(uint256 indexed txIndex, address indexed approver);

    EnumerableSet.AddressSet private restrictedAddresses;
    address[] public approvers;
    mapping(address => bool) public isApprover;
    uint256 public required;
    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public approved;

    /**
     * @dev Modifier to check if a transaction exists.
     * @param _txIndex The index of the transaction.
     */
    modifier txExists(uint256 _txIndex) {
        require(_txIndex < transactions.length, "tx does not exist");
        _;
    }

    /**
     * @dev Modifier to check if a transaction has not been executed.
     * @param _txIndex The index of the transaction.
     */
    modifier notExecuted(uint256 _txIndex) {
        require(!transactions[_txIndex].executed, "tx already executed");
        _;
    }

    /**
     * @dev Modifier to check if a transaction has not been approved by the caller.
     * @param _txIndex The index of the transaction.
     */
    modifier notApproved(uint256 _txIndex) {
        require(!approved[_txIndex][_msgSender()], "tx already approved");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with a list of approvers and the required number of approvals.
     * @param _approver The list of addresses that can approve transactions.
     * @param _required The number of approvals required for a transaction to be executed.
     */
    function initialize(
        address[] memory _approver,
        uint256 _required
    ) public initializer {
        __ERC20_init("eXchange1", "eX1");
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        
        require(_approver.length > 0, "Approver required");
        require(_required > 0 && _required <= _approver.length, "invalid required number");

        for (uint256 i = 0; i < _approver.length; i++) {
            address approver = _approver[i];
            require(approver != address(0), "invalid approver");
            require(!isApprover[approver], "approver not unique");

            isApprover[approver] = true;
            _grantRole(APPROVER_ROLE, approver);
            approvers.push(approver);
        }
        required = _required;
        
        _mint(_msgSender(), 369_000_000 * 10 ** 18);
    }

    /**
     * @dev Updates the status of approvers.
     * @param _approver The list of approver addresses to update.
     * @param status The list of statuses to set for each approver.
     */
    function updateApprovers(address[] memory _approver, bool[] memory status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_approver.length == status.length, "Lenght Mismatched!");
        for(uint i = 0; i< _approver.length; i++) {
            isApprover[_approver[i]] = status[i];
        }
    }

    /**
     * @dev Adds an address to the restricted list.
     * @param _address The address to restrict.
     */
    function addRestrictedAddress(address _address) external onlyRole(OWNER_ROLE) {
        restrictedAddresses.add(_address);
    }

    /**
     * @dev Removes an address from the restricted list.
     * @param _address The address to remove from the restricted list.
     */
    function removeRestrictedAddress(address _address) external onlyRole(OWNER_ROLE) {
        restrictedAddresses.remove(_address);
    }

    /**
     * @dev Checks if an address is restricted.
     * @param _address The address to check.
     * @return bool Whether the address is restricted.
     */
    function isAddressRestricted(address _address) public view returns (bool) {
        return restrictedAddresses.contains(_address);
    }

    /**
     * @dev Overrides the ERC20 transfer function to handle restricted addresses.
     * @param _to The address to transfer tokens to.
     * @param _value The amount of tokens to transfer.
     * @return bool Whether the transfer was successful.
     */
    function transfer(address _to, uint256 _value) public virtual override returns (bool) {
        if (isAddressRestricted(_msgSender())) {
            uint256 txIndex = _proposeTransfer(_msgSender(), _to, _value);
            emit TransferProposed(txIndex, _msgSender(), _to, _value);
        } else {
            _transfer(_msgSender(), _to, _value);
        }
        return true;
    }

    /**
     * @dev Proposes a new transfer transaction.
     * @param _from The address initiating the transfer.
     * @param _to The address receiving the tokens.
     * @param _value The amount of tokens to transfer.
     * @return uint256 The index of the proposed transaction.
     */
    function _proposeTransfer(address _from, address _to, uint256 _value) internal returns (uint256) {
        transactions.push(Transaction({
            from: _from,
            to: _to,
            value: _value,
            executed: false,
            approvalCount: 0
        }));
        
        return transactions.length - 1;
    }

    /**
     * @dev Proposes a new transfer transaction (external version).
     * @param _from The address initiating the transfer.
     * @param _to The address receiving the tokens.
     * @param _value The amount of tokens to transfer.
     * @return uint256 The index of the proposed transaction.
     */
    function proposeTransfer(address _from, address _to, uint256 _value) external onlyRole(APPROVER_ROLE) returns (uint256) {
        require(isApprover[_msgSender()] == true, "Approver Status Held!");
        transactions.push(Transaction({
            from: _from,
            to: _to,
            value: _value,
            executed: false,
            approvalCount: 0
        }));
        
        return transactions.length - 1;
    }

    /**
     * @dev Approves a proposed transfer transaction.
     * @param _txIndex The index of the transaction to approve.
     */
    function approveTransfer(uint256 _txIndex)
        public
        onlyRole(APPROVER_ROLE)
        txExists(_txIndex)
        notExecuted(_txIndex)
        notApproved(_txIndex)
    {
        require(isApprover[_msgSender()] == true, "Approver Status Held!");

        approved[_txIndex][_msgSender()] = true;
        transactions[_txIndex].approvalCount += 1;

        emit TransferApproved(_txIndex, _msgSender());

        if (transactions[_txIndex].approvalCount >= required) {
            executeTransfer(_txIndex);
        }
    }

    /**
     * @dev Revokes approval for a proposed transfer transaction.
     * @param _txIndex The index of the transaction to revoke approval for.
     */
    function revokeApproval(uint256 _txIndex)
        public
        onlyRole(APPROVER_ROLE)
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        require(isApprover[_msgSender()] == true, "Approver Status Held!");
        
        require(approved[_txIndex][_msgSender()], "tx not approved");

        approved[_txIndex][_msgSender()] = false;
        transactions[_txIndex].approvalCount -= 1;

        emit ApprovalRevoked(_txIndex, _msgSender());
    }

    /**
     * @dev Executes a proposed transfer transaction.
     * @param _txIndex The index of the transaction to execute.
     */
    function executeTransfer(uint256 _txIndex)
        public
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        require(transactions[_txIndex].approvalCount >= required, "not enough approvals");

        Transaction storage transaction = transactions[_txIndex];
        require(!transaction.executed, "transfer already executed");

        transaction.executed = true;
        _transfer(transaction.from, transaction.to, transaction.value);

        emit TransferExecuted(_txIndex);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}