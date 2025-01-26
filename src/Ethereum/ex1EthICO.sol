// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23; 

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Ex1ICO is Initializable, ReentrancyGuardUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    struct IcoStage{
        bool active;
        uint256 icoStageID;
    }
    mapping(uint256 => IcoStage) public icoStages;

    mapping(address => uint256) public HoldersCummulativeBalance;
    mapping(uint256 => mapping(address => uint256)) public userDepositsPerICOStage;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier checkSaleStatus(uint256 _icoStageID) {
        require(
            icoStages[_icoStageID].active == true, 
            "ICO Stage Not Active"
        );
        _;
    }

    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
    }

    function purchasedViaEth(
        uint256 amount,
        uint256 _icoStageID
    ) external checkSaleStatus(_icoStageID) payable nonReentrant {
                
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}