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
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");


    enum ApprovalStatus {
        pending,
        revoked,
        exectued
    }

    /**
     * @dev Struct representing a proposed transaction.
     * @param from The address initiating the transfer.
     * @param to The address receiving the tokens.
     * @param value The amount of tokens to transfer.
     * @param executed Whether the transaction has been executed.
     * @param approvalCount The number of approvals the transaction has received.
     */
    struct Transaction {
        uint256 proposalID;
        address from;
        address to;
        uint256 value;
        bool executed;
        uint256 approvalCount;
        uint256 revokeCount;
        ApprovalStatus approvalStatus;
    }

    event TransferProposed(uint256 indexed txIndex, address indexed proposer, address indexed to, uint256 value);
    event TransferApproved(uint256 indexed txIndex, address indexed approver);
    event TransferExecuted(uint256 indexed txIndex);
    event ApprovalRevoked(uint256 indexed txIndex, address indexed approver);

    EnumerableSet.AddressSet private restrictedAddresses;

    address[] public approvers;
    uint256 public required;
    uint256 public totalMulitisigProposals;

    mapping(address => bool) public isApprover;
    mapping(uint256 => bool) public isRevoked;
    /// For Vote = Approve, approved value = 1 and for vote = Revoke, approved value = 2
    mapping(uint256 => mapping(address => uint256)) public voteNature;
    mapping(uint256 => mapping(uint256 => bool)) public approvalStatus;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => Transaction) public transactions;
    
    /**
     * @dev Modifier to check if a transaction exists.
     * @param _txIndex The index of the transaction.
     */
    modifier txExists(uint256 _txIndex) {
        require(_txIndex <= totalMulitisigProposals, "tx does not exist");
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
    modifier notVoted(uint256 _txIndex) {
        require(!hasVoted[_txIndex][_msgSender()], "tx already approved");
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
        _grantRole(EXECUTOR_ROLE, _msgSender());
        _grantRole(OWNER_ROLE, _msgSender());
        
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
        require(_approver.length == status.length, "Length Mismatched!");
        for(uint i = 0; i< _approver.length; i++) {
            isApprover[_approver[i]] = status[i];
        }
    }

    /**
     * @dev Add approvers.
     * @param _approver The list of approver addresses to be added.
     */
    function addApprover(address[] memory _approver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < _approver.length; i++) {
            address approver = _approver[i];
            require(approver != address(0), "invalid approver");
            require(!isApprover[approver], "approver not unique");

            isApprover[approver] = true;
            _grantRole(APPROVER_ROLE, approver);
            approvers.push(approver);
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
    * @dev Returns list of restricted addresses.
    * @return address[] List of restricted addresses.
    */
    function checkRestrictedAddress() public view returns(bytes32[] memory) {
        return restrictedAddresses._inner._values;
    }

    /**
     * @dev Queries list of Approvers Address.
     * @return address[] List of Approvers Address.
     */
    function checkApprovers() public view returns(address[] memory) {
        address[] memory approverList = new address[](approvers.length);
        for(uint256 i = 0; i< approvers.length; i++) {
            approverList[i] = approvers[i];
        }
        return approverList;
    }

    /**
     * @dev Overrides the ERC20 transfer function to handle restricted addresses.
     * @param _to The address to transfer tokens to.
     * @param _value The amount of tokens to transfer.
     * @return bool Whether the transfer was successful.
     */
    function transfer(address _to, uint256 _value) public virtual override returns (bool) {
        if (isAddressRestricted(_msgSender()) == true) {
            _proposeTransfer(_msgSender(), _to, _value);
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
     */
    function _proposeTransfer(address _from, address _to, uint256 _value) internal {
        uint256 _proposalID = totalMulitisigProposals +=1;
        transactions[_proposalID] = Transaction({
            proposalID: _proposalID,
            from: _from,
            to: _to,
            value: _value,
            executed: false,
            approvalCount: 0,
            revokeCount: 0,
            approvalStatus: ApprovalStatus.pending
        });
        emit TransferProposed(_proposalID, _msgSender(), _to, _value);      
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
        notVoted(_txIndex)
    {
        require(isApprover[_msgSender()] == true, "Approver Status Held!");
        require(isRevoked[_txIndex] == false, "Transaction status Revoked!");
        require(transactions[_txIndex].executed == false, "Transaction already Executed");
        require(hasVoted[_txIndex][_msgSender()] == false, "Approver already Voted");

        voteNature[_txIndex][_msgSender()] = 1;
        transactions[_txIndex].approvalCount += 1;
        hasVoted[_txIndex][_msgSender()] = true;

        emit TransferApproved(_txIndex, _msgSender());

        if (transactions[_txIndex].approvalCount >= required) {
            _executeTransfer(_txIndex);
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
        require(isRevoked[_txIndex] == false, "Transaction status Revoked!");
        require(hasVoted[_txIndex][_msgSender()] == false, "Approver already Voted");
        require(transactions[_txIndex].executed == false, "Transaction already Executed");

        voteNature[_txIndex][_msgSender()] = 2;
        transactions[_txIndex].revokeCount += 1;

        if (transactions[_txIndex].revokeCount > required) {
            transactions[_txIndex].approvalStatus = ApprovalStatus.revoked;
        }

        emit ApprovalRevoked(_txIndex, _msgSender());
    }

    /**
     * @dev Executes a proposed transfer transaction.
     * @param _txIndex The index of the transaction to execute.
     */
    function _executeTransfer(uint256 _txIndex)
        internal
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        require(transactions[_txIndex].approvalCount >= required, "not enough approvals");

        Transaction storage transaction = transactions[_txIndex];
        require(!transaction.executed, "transfer already executed");

        transaction.executed = true;
        transactions[_txIndex].approvalStatus = ApprovalStatus.exectued;
        _transfer(transaction.from, transaction.to, transaction.value);

        emit TransferExecuted(_txIndex);
    }

    function executeTransfer(uint256 _txIndex)
        external 
        txExists(_txIndex)
        notExecuted(_txIndex)
        onlyRole(DEFAULT_ADMIN_ROLE)
        onlyRole(EXECUTOR_ROLE) 
    {
        _executeTransfer(_txIndex);
    }


    /**
    * @dev Fetches all the Pending Proposals
    */
    function getAllPendingProposals() external view returns (Transaction[] memory) {
        uint256 pendingCount = 0;
        for (uint256 i = 1; i <= totalMulitisigProposals; i++) {
            if (transactions[i].approvalStatus == ApprovalStatus.pending) {
                pendingCount++;
            }
        }

        Transaction[] memory pendingTransactions = new Transaction[](pendingCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= totalMulitisigProposals; i++) {
            if (transactions[i].approvalStatus == ApprovalStatus.pending) {
                pendingTransactions[index] = transactions[i];
                index++;
            }
        }
        return pendingTransactions;
    }

    /**
    * @dev Update required minimum approvals
    * @param _required The new minimum required approvals 
    */
    function updateRequiredApprovers(uint256 _required) external onlyRole(OWNER_ROLE) {
        required = _required;
    }

    /**
     * @dev Authorizes an upgrade to a new implementation.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}