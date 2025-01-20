// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./Interfaces/InterfaceEx1ICO.sol";
import "./Interfaces/InterfaceEx1Vesting.sol";

contract Ex1Staking is Initializable, ReentrancyGuardUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    Iex1ICO public icoInterface = Iex1ICO(0x301Cc53ff52Bf79C15249fa25d1e8aE8e222F205);
    IVestingICO public vestingInterface = IVestingICO(0x301Cc53ff52Bf79C15249fa25d1e8aE8e222F205);
    IERC20 public ex1Token;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant STAKING_AUTHORISER_ROLE = keccak256("STAKING_AUTHORISER_ROLE"); 

    struct StakingParamter {
        uint256 percentageReturn;
        uint256 timePeriodInSeconds;
        uint256 _icoStageID;
        uint256 _stakingEndTime;
    }
    mapping(uint256 => StakingParamter) public stakingParameters;

    mapping(uint256 => mapping(address => bool)) public isStaked;
    mapping(uint256 => mapping(address => uint256)) public stakeTimestamp;
    mapping(uint256 => mapping(address => uint256)) public previousStakingRewardClaimTimestamp;

    event StakingRewardClaimed(
        address indexed staker,
        uint256 amount,
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
        @dev Function to create staking rewards parameters
        @param _percentageReturn: The percentage of the staking reward
        @param _timePeriodInSeconds: The time period in seconds over which a staking reward is calculated. 
        * For example, if the time period is 30 days, the staking reward will be calculated over 30 days
        @param _icoStageID: The ID of the ICO stage
    */
    function createStakingRewardsParamaters(
        uint256 _percentageReturn,
        uint256 _timePeriodInSeconds,
        uint256 _icoStageID
    ) external onlyRole(STAKING_AUTHORISER_ROLE) {
        ( , uint256 startTime, , , ) = vestingInterface.claimSchedules(_icoStageID);
        require(
            _percentageReturn > 0 && _percentageReturn <= 100,
            "ex1Presale: Invalid Percentage!"
        );
        require(
            _timePeriodInSeconds > 0,
            "ex1Presale: Invalid Time Period!"
        );
        require(
            startTime > block.timestamp,
            "ex1Presale: Vesting Schedule Claiming already Initiated"
        );
        stakingParameters[_icoStageID] = StakingParamter({
            percentageReturn: _percentageReturn,
            timePeriodInSeconds: _timePeriodInSeconds,
            _icoStageID: _icoStageID,
            _stakingEndTime: startTime - 1
        });
    }

    /**
        @dev Function to stake tokens
        @param _icoStageID: The ID of the ICO stage
    */
    function stake(
        uint256 _icoStageID
    ) external returns(bool) {
        uint256 deposits = icoInterface.userDepositsPerICOStage(_icoStageID, _msgSender());
        ( , uint256 startTime, , , ) = vestingInterface.claimSchedules(_icoStageID);

        require(
            deposits > 0,
            "ex1Presale: No Tokens to Stake!"
        );
        require(
            block.timestamp <= startTime,
            "ex1Presale: Staking Not Active!"
        );
        require(
            !isStaked[_icoStageID][_msgSender()],
            "ex1Presale: Already Staked!"
        );
        isStaked[_icoStageID][_msgSender()] = true;
        stakeTimestamp[_icoStageID][_msgSender()] = block.timestamp;
        previousStakingRewardClaimTimestamp[_icoStageID][_msgSender()] = 0;
        return true;
    }

    /**
        @dev Function to claim staking rewards
        @param _icoStageID: The ID of the ICO stage
    */
    function claimStakingRewards(
        uint256 _icoStageID
    ) external nonReentrant {
        require(
            !isStaked[_icoStageID][_msgSender()], 
            "ex1Presale: Not Staked Yet!"
        );
        uint256 reward = calculateStakeReward(_icoStageID, _msgSender());
        require(
            reward > 0,
            "ex1Presale: No Rewards to Claim!"
        );
        bool success = IERC20(ex1Token).transfer(_msgSender(), reward);
        require(
            success,
            "ex1Presale: Token Transfer Failed!"
        );         
        emit StakingRewardClaimed(
            _msgSender(),
            reward,
            block.timestamp
        );       
    }

    /**
        @dev Internal Function to calculate the staking reward
        @param _icoStageID: The ID of the ICO stage
        @param _caller: The address of the caller
    */
    function calculateStakeReward(
        uint256 _icoStageID,
        address _caller
    ) internal returns(uint256) {    
        require(
            isStaked[_icoStageID][_caller],
            "ex1Presale: Not Staked Yet!"
        );
        uint256 deposits = icoInterface.userDepositsPerICOStage(_icoStageID, _caller);
        uint256 userPercentage = (deposits * (stakingParameters[_icoStageID].percentageReturn)) / 100;
        uint256 userRewardPerSecond = userPercentage / stakingParameters[_icoStageID].timePeriodInSeconds;
        uint256 reward;

        if (block.timestamp < stakingParameters[_icoStageID]._stakingEndTime) {
            if (previousStakingRewardClaimTimestamp[_icoStageID][_caller] == 0) {
                reward = ((block.timestamp - stakeTimestamp[_icoStageID][_caller]) * userRewardPerSecond);
                previousStakingRewardClaimTimestamp[_icoStageID][_caller] = block.timestamp;
            }
            else {
                reward = ((block.timestamp - previousStakingRewardClaimTimestamp[_icoStageID][_caller]) * userRewardPerSecond);
                previousStakingRewardClaimTimestamp[_icoStageID][_caller] = block.timestamp;
            }            
        } else {
            reward = ((stakingParameters[_icoStageID]._stakingEndTime - previousStakingRewardClaimTimestamp[_icoStageID][_caller]) * userRewardPerSecond);
            isStaked[_icoStageID][_caller] = false;
        }
        return reward;
    }
    /**
        @dev Function to view claimable rewards
        @param _icoStageID: The ID of the ICO stage
        @param _caller: The address of the caller
    */
    function viewClaimableRewards(
        uint256 _icoStageID,
        address _caller
    ) external view returns(uint256) {
        require(
            isStaked[_icoStageID][_caller],
            "ex1Presale: Not Staked Yet!"
        );
        uint256 deposits = icoInterface.userDepositsPerICOStage(_icoStageID, _caller);
        uint256 userPercentage = deposits * (stakingParameters[_icoStageID].percentageReturn / 100);
        uint256 userRewardPerSecond = userPercentage / stakingParameters[_icoStageID].timePeriodInSeconds;
        uint256 reward;
        if(previousStakingRewardClaimTimestamp[_icoStageID][_caller] == 0) {
            return reward = reward = ((block.timestamp - stakeTimestamp[_icoStageID][_caller]) * userRewardPerSecond);
        }
        else {
            return reward = reward = ((block.timestamp - previousStakingRewardClaimTimestamp[_icoStageID][_caller]) * userRewardPerSecond);
        }
    }

    /**
        @dev Function to unstake tokens
        @param _icoStageID: The ID of the ICO stage
    */
    function unstake(
        uint256 _icoStageID
    ) external returns(bool) {
        require(
            isStaked[_icoStageID][_msgSender()],
            "ex1Presale: Not Staked Yet!"
        );
        isStaked[_icoStageID][_msgSender()] = false;
        return true;
    }

    function updateIcoInterface(
        Iex1ICO _icoInterface
    ) external onlyRole(OWNER_ROLE) {
        icoInterface = _icoInterface;
    }

    function updateVestingInterface(
        IVestingICO _vestingInterface
    ) external onlyRole(OWNER_ROLE) {
        vestingInterface = _vestingInterface;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

}