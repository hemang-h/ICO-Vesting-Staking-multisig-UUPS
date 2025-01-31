// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract EX1 is Initializable, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant ADDER_ROLE = keccak256("ADDER_ROLE");
    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");

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

    function initialize(
        address[] memory _approver,
        uint256 _required
    ) public initializer {
        __ERC20_init("eXchange1", "eX1");
        __AccessControl_init();
        __UUPSUpgradeable_init();
        
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
        
        _mint(msg.sender, 369_000_000 * 10 ** 18);
    }

    function updateApprovers(address[] memory _approver, bool[] memory status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_approver.length == status.length, "Lenght Mismatched!");
        for(uint i = 0; i< _approver.length; i++) {
            isApprover[_approver[i]] = status[i];
        }
    }

    function addRestrictedAddress(address _address) external onlyRole(OWNER_ROLE) {
        restrictedAddresses.add(_address);
    }

    function removeRestrictedAddress(address _address) external onlyRole(OWNER_ROLE) {
        restrictedAddresses.remove(_address);
    }

    function isAddressRestricted(address _address) public view returns (bool) {
        return restrictedAddresses.contains(_address);
    }

    function transfer(address _to, uint256 _value) public virtual override returns (bool) {
        if (isAddressRestricted(_msgSender())) {
            uint256 txIndex = _proposeTransfer(_msgSender(), _to, _value);
            emit TransferProposed(txIndex, _msgSender(), _to, _value);
        } else {
            _transfer(_msgSender(), _to, _value);
        }
        return true;
    }

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

    function proposeTransfer(address _from, address _to, uint256 _value) external onlyRole(APPROVER_ROLE) returns (uint256) {
        require(isApprover[msg.sender] == true, "Approver Status Held!");
        transactions.push(Transaction({
            from: _from,
            to: _to,
            value: _value,
            executed: false,
            approvalCount: 0
        }));
        
        return transactions.length - 1;
    }

    function approveTransfer(uint256 _txIndex)
        public
        onlyRole(APPROVER_ROLE)
        txExists(_txIndex)
        notExecuted(_txIndex)
        notApproved(_txIndex)
    {
        require(isApprover[msg.sender] == true, "Approver Status Held!");

        approved[_txIndex][msg.sender] = true;
        transactions[_txIndex].approvalCount += 1;

        emit TransferApproved(_txIndex, msg.sender);

        if (transactions[_txIndex].approvalCount >= required) {
            executeTransfer(_txIndex);
        }
    }

    function revokeApproval(uint256 _txIndex)
        public
        onlyRole(APPROVER_ROLE)
        txExists(_txIndex)
        notExecuted(_txIndex)
    {
        require(isApprover[msg.sender] == true, "Approver Status Held!");
        
        require(approved[_txIndex][msg.sender], "tx not approved");

        approved[_txIndex][msg.sender] = false;
        transactions[_txIndex].approvalCount -= 1;

        emit ApprovalRevoked(_txIndex, msg.sender);
    }

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

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}