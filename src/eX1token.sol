// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.23;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract EXchange1 is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public minimumThreshold;

    mapping(address => bool) whitelistedWallet;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address upgrader)
        initializer public
    {
        __ERC20_init("eXchange1", "eX1");
        __ERC20Permit_init("eXchange1");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _mint(msg.sender, 369000000 * 10 ** decimals());
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, upgrader);
    }

    // function transfer(address to, uint256 value) public virtual override {
    //     if(whitelistedWallet[to] == true) {
            
    //     } 
    //     else _transfer(to, value);
    // }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}