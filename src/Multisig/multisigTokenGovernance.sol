// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract MultiSigWallet is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant OWNER_ROLE = ("OWNER_ROLE");

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 approvalCount;
    }

    event TransactionProposed(uint256 indexed txIndex, address indexed proposer);
    event TransactionApproved(uint256 indexed txIndex, address indexed approver);
    event TransactionExecuted(uint256 indexed txIndex);
    event ApprovalRevoked(uint256 indexed txIndex, address indexed approver);

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public required;
    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public approved;

    modifier txExists(uint256 _txIndex) {
        require(_txIndex < transactions.length, "tx does not exist");
        _;
    }

    modifier notExecuted(uint256 _txIndex) {
        require(!transactions[_txIndex].executed, "tx already executed");
        _;
    }

    modifier notApproved(uint256 _txIndex) {
        require(!approved[_txIndex][msg.sender], "tx already approved");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address[] memory _owners, uint256 _required) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        require(_owners.length > 0, "owners required");
        require(_required > 0 && _required <= _owners.length, "invalid required number");

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner not unique");

            isOwner[owner] = true;
            _grantRole(OWNER_ROLE, owner);
            owners.push(owner);
        }
        required = _required;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function propose(address _to, uint256 _value, bytes memory _data)
        public
        onlyRole(OWNER_ROLE)
        returns (uint256)
    {
        transactions.push(Transaction({
            to: _to,
            value: _value,
            data: _data,
            executed: false,
            approvalCount: 0
        }));

        uint256 txIndex = transactions.length - 1;
        emit TransactionProposed(txIndex, msg.sender);
        return txIndex;
    }

    function approve(uint256 _txIndex)
        public
        onlyRole(OWNER_ROLE)
        txExists(_txIndex)
        notExecuted(_txIndex)
        notApproved(_txIndex)
    {
        approved[_txIndex][msg.sender] = true;
        transactions[_txIndex].approvalCount += 1;

        if(transactions[_txIndex].approvalCount >= required) {
            execute(_txIndex);
        }

        emit TransactionApproved(_txIndex, msg.sender);
    }

    function revokeApproval(uint256 _txIndex)
        public
        onlyRole(OWNER_ROLE)
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        require(approved[_txIndex][msg.sender], "tx not approved");

        approved[_txIndex][msg.sender] = false;
        transactions[_txIndex].approvalCount -= 1;

        emit ApprovalRevoked(_txIndex, msg.sender);
    }

    function execute(uint256 _txIndex)
        public
        onlyRole(OWNER_ROLE)
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        require(
            transactions[_txIndex].approvalCount >= required,
            "not enough approvals"
        );

        Transaction storage transaction = transactions[_txIndex];
        transaction.executed = true;

        (bool success, ) = transaction.to.call{value: transaction.value}(
            transaction.data
        );
        require(success, "tx failed");

        emit TransactionExecuted(_txIndex);
    }
}