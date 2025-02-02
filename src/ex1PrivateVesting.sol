// SPDX-License-Identifier:MIT

pragma solidity ^0.8.23;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PrivateVesting is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant VESTING_CREATOR_ROLE = keccak256("VESTING_CREATOR_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    
    struct Vesting {
        address beneficiary;
        uint256 TotalAmount;
        uint256 startTime;
        uint256 endTime;
        uint256 claimInterval;
    }
    
    constructor() {
        _disableInitializers();
    }

    function initialise() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
    }

    function createVesting(
        address _beneficary,
        uint256 _totalAmount,
        uint256 _startTime,
        uint256 _endTime
    ) external onlyRole(VESTING_CREATOR_ROLE) {

    }

    function updateVesting() external onlyRole(VESTING_CREATOR_ROLE){

    }

    function setEx1TokenSaleContract() external onlyRole(OWNER_ROLE) {

    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}
