// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./Interfaces/InterfaceEx1ICO.sol";

contract ex1ICOVesting is Initializable, ReentrancyGuardUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    Iex1ICO public icoInterface = Iex1ICO(0x301Cc53ff52Bf79C15249fa25d1e8aE8e222F205);
    IERC20 public ex1Token;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant VESTING_AUTHORISER_ROLE = keccak256("VESTING_AUTHORISER_ROLE");

    struct claimSchedule {
        uint256 icoStageID;
        uint256 startTime;
        uint256 endTime;
        uint256 interval;
        uint256 slicePeriod;
    }

    mapping(address => bool) public isClaimed; 
    mapping(address => uint256) public prevClaimTimestamp;

    mapping(uint256 => mapping(address => uint256)) public UserClaimedPerICOStage;
    mapping(uint256 => mapping(address => uint256)) public claimedAmount;

    mapping(uint256 => claimSchedule) public claimSchedules;

    event ClaimScheduleCreated(
        uint256 indexed icoStageID,
        uint256 startTime,
        uint256 endTime,
        uint256 interval,
        uint256 slicePeriod,
        uint256 timestamp
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

     /**
        @dev Function to set the claim schedule
        @param _icoStageID: The ID of the ICO stage
        @param _startTime: The start time of the claim schedule in unix timestamp
        @param _endTime: The end time of the claim schedule in unix timestamp
        @param _claimInterval: The interval between each claim
        @param _slicePeriod: The period to slice the claim
    */
    function setClaimSchedule(
        uint256 _icoStageID,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _claimInterval,
        uint256 _slicePeriod
    ) external onlyRole(VESTING_AUTHORISER_ROLE){
        ( , uint256 endTime, , , ) = icoInterface.icoStages(_icoStageID);
        require(
            _startTime > endTime, 
            "ex1Presale: Token Sale not Ended yet!"
        );
        require(
            (_endTime > _startTime) && 
            (_startTime > 0 || _endTime > 0) && 
            (_endTime > block.timestamp) && 
            (_startTime > block.timestamp),
            "ex1Presale: Invalid Schedule or Parameters!"
        );
        require(
            _claimInterval <= (_endTime - _startTime),
            "ex1Presale: Invalid Cliff Period"
        );
        require(
            _slicePeriod >= 0 && _slicePeriod <= 60, 
            "ex1Presale: Invalid Slice Period"
        );
        
        claimSchedules[_icoStageID] = claimSchedule({
            icoStageID: _icoStageID,
            startTime: _startTime,
            endTime: _endTime,
            interval: _claimInterval,
            slicePeriod: _slicePeriod
        });
        emit ClaimScheduleCreated(
            _icoStageID,
            _startTime,
            _endTime,
            _claimInterval,
            _slicePeriod,
            block.timestamp
        );
    }

    /**
        @dev Function to update the claim schedule
    */
    function updateClaimSchedule(
        uint256 _icoStageID,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _claimInterval,
        uint256 _slicePeriod
    ) external onlyRole(VESTING_AUTHORISER_ROLE) {
        require(
            _startTime == claimSchedules[_icoStageID].startTime,
            "ex1Presale: Claim Schedule Already Started!"
        );
        require(
            (_endTime > _startTime) && 
            (_startTime > 0 || _endTime > 0) && 
            (_endTime > block.timestamp) && 
            (_startTime > block.timestamp),
            "ex1Presale: Invalid Schedule or Parameters!"
        );
        require(
            _claimInterval <= (_endTime - _startTime),
            "ex1Presale: Invalid Cliff Period"
        );
        require(
            _slicePeriod >= 0 && _slicePeriod <= 60, 
            "ex1Presale: Invalid Slice Period"
        );

        claimSchedules[_icoStageID].startTime = _startTime;
        claimSchedules[_icoStageID].endTime = _endTime;
        claimSchedules[_icoStageID].interval = _claimInterval;
        claimSchedules[_icoStageID].slicePeriod = _slicePeriod;
    }

    /**
        @dev Function to claim tokens
        @param _icoStageID: The ico stage for which claim is been made
    */
    function claimTokens(
        uint256 _icoStageID
    ) external nonReentrant returns(bool) {
        require(
            block.timestamp >= claimSchedules[_icoStageID].startTime 
            && block.timestamp <= claimSchedules[_icoStageID].endTime,
            "ex1Presale: Claim Not Active!"
        );
        bool exists = icoInterface.HoldersExist(_icoStageID, _msgSender());
        require(
            exists,
            "ex1Presale: Holder doesn't Exists!"
        );
        uint256 deposits = icoInterface.userDepositsPerICOStage(_icoStageID, _msgSender());
        require(
            deposits > 0,
            "ex1Presale: No Tokens to Claim!"
        );
        uint256 claimableAmount = calculateClaimableAmount(_msgSender(), _icoStageID);
        require(
            claimableAmount > 0,
            "ex1Presale: No Tokens to Claim!"
        );
        require(
            block.timestamp - prevClaimTimestamp[msg.sender] >= claimSchedules[_icoStageID].interval,
            "ex1Presale: Claim Interval Not Reached!"
        );

        claimedAmount[_icoStageID][msg.sender] += claimableAmount;
        prevClaimTimestamp[msg.sender] = block.timestamp;

        bool success = IERC20(ex1Token).transfer(msg.sender, claimableAmount);
        require(
            success,
            "ex1Presale: Token Transfer Failed!"
        );
        return true;
    }  

    /**
        @dev Function to calculate the claimable amount
        @param _caller: The address of the caller
        @param _icoStageID: The ID of the ICO stage
    */
    function calculateClaimableAmount(
        address _caller,
        uint256 _icoStageID
    ) public nonReentrant returns(uint256) {
        claimSchedule memory schedule = claimSchedules[_icoStageID];

        uint256 totalDeposits = icoInterface.userDepositsPerICOStage(_icoStageID, _caller);
        uint256 totalNumberOfSlices = (schedule.endTime - schedule.endTime) / schedule.slicePeriod;
        uint256 tokenPerSlice = totalDeposits / totalNumberOfSlices;

        uint256 elapsedSlices = (block.timestamp - schedule.startTime) / schedule.slicePeriod;
        uint256 claimable = tokenPerSlice * elapsedSlices - claimedAmount[_icoStageID][msg.sender];

        return claimable;
    } 

    function updateInterface(
        Iex1ICO _icoInterface
    ) external onlyRole(OWNER_ROLE) {
        icoInterface = _icoInterface;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}