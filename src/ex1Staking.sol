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

    Iex1ICO public icoInterface;
    IVestingICO public vestingInterface;
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
    mapping(uint256 => mapping(address => bool)) public unstaked;
    mapping(uint256 => mapping(address => uint256)) public totalStakedPerICO;
    mapping(uint256 => mapping(address => uint256)) public stakeTimestamp;
    mapping(uint256 => mapping(address => uint256)) public unstakeTimestamp;
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
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(OWNER_ROLE, _msgSender());
        _grantRole(UPGRADER_ROLE, _msgSender());
        _grantRole(STAKING_AUTHORISER_ROLE, _msgSender());
        icoInterface = Iex1ICO(0x9B8E8c8046763c311b48C56509959104d1AcE1EF);
        vestingInterface = IVestingICO(0x7ed257733357d1FDCe59a54B94fbaB75990cfCB7);
        ex1Token = IERC20(0x6B1fdD1E4b2aE9dE8c5764481A8B6d00070a3096);
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
            "ex1Staking: Invalid Percentage!"
        );
        require(
            _timePeriodInSeconds > 0,
            "ex1Staking: Invalid Time Period!"
        );
        require (
            startTime > 0, 
            "ex1Staking: Vesting Schedule not set for this ICO stage!"
        );
        require(
            startTime > block.timestamp,
            "ex1Staking: Vesting Schedule Claiming already Initiated"
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
        uint256 deposits = icoInterface.UserDepositsPerICOStage(_icoStageID, _msgSender());
        ( , uint256 startTime, , , ) = vestingInterface.claimSchedules(_icoStageID);
        require(
            getEligibleStakableToken(_icoStageID, _msgSender())> 0,
            "ex1staking: No Balance available to stake"
        );
        require(
            deposits > 0,
            "ex1Staking: No Tokens to Stake!"
        );
        require(
            block.timestamp <= startTime,
            "ex1Staking: Staking Not Active!"
        );

        isStaked[_icoStageID][_msgSender()] = true;
        totalStakedPerICO[_icoStageID][_msgSender()] = deposits;
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
            isStaked[_icoStageID][_msgSender()], 
            "ex1Staking: Not Staked Yet!"
        );
        uint256 reward = calculateStakeReward(_icoStageID, _msgSender());
        require(
            reward > 0,
            "ex1Staking: No Rewards to Claim!"
        );
        bool success = IERC20(ex1Token).transfer(_msgSender(), reward);
        require(
            success,
            "ex1Staking: Token Transfer Failed!"
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
            "ex1Staking: Not Staked Yet!"
        );
        uint256 deposits = totalStakedPerICO[_icoStageID][_caller];
        uint256 userPercentage = (deposits * (stakingParameters[_icoStageID].percentageReturn)) / 100;
        uint256 userRewardPerSecond = userPercentage / stakingParameters[_icoStageID].timePeriodInSeconds;
        uint256 reward;
        uint256 time;
        uint256 unstakeTime = unstakeTimestamp[_icoStageID][_caller];
        uint256 stakingEndTime = stakingParameters[_icoStageID]._stakingEndTime;
        if(unstaked[_icoStageID][_caller] == true && block.timestamp > stakingEndTime) {
            time = unstakeTime; 
            stakingEndTime = unstakeTime;
        } else if (unstaked[_icoStageID][_caller] == true ) {
            time = unstakeTime;
        }
        else {
            time = block.timestamp;
        }

        if (block.timestamp < stakingEndTime) {
            if (previousStakingRewardClaimTimestamp[_icoStageID][_caller] == 0) {
                reward = ((time - stakeTimestamp[_icoStageID][_caller]) * userRewardPerSecond);
                previousStakingRewardClaimTimestamp[_icoStageID][_caller] = block.timestamp;
                return reward;
            }
            else {
                reward = ((time - previousStakingRewardClaimTimestamp[_icoStageID][_caller]) * userRewardPerSecond);
                previousStakingRewardClaimTimestamp[_icoStageID][_caller] = block.timestamp;
                return reward;
            }            
        } else {
            reward = ((stakingEndTime - previousStakingRewardClaimTimestamp[_icoStageID][_caller]) * userRewardPerSecond);
            isStaked[_icoStageID][_caller] = false;
            unstaked[_icoStageID][_caller] = true;
            return reward;
        }
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
            "ex1Staking: Not Staked Yet!"
        );
        uint256 deposits = totalStakedPerICO[_icoStageID][_caller]; 
        uint256 userPercentage = (deposits * stakingParameters[_icoStageID].percentageReturn )/ 100; 
        uint256 userRewardPerSecond = userPercentage / stakingParameters[_icoStageID].timePeriodInSeconds; 
        uint256 reward;
        uint256 time;
        uint256 unstakeTime = unstakeTimestamp[_icoStageID][_caller];
        uint256 stakingEndTime = stakingParameters[_icoStageID]._stakingEndTime;
        if(unstaked[_icoStageID][_caller] == true && block.timestamp > stakingEndTime) {
            time = unstakeTime; 
            stakingEndTime = unstakeTime;
        } else if (unstaked[_icoStageID][_caller] == true ) {
            time = unstakeTime;
        }
        else {
            time = block.timestamp;
        }
        if (block.timestamp < stakingEndTime) {
            if (previousStakingRewardClaimTimestamp[_icoStageID][_caller] == 0) {
                reward = ((time - stakeTimestamp[_icoStageID][_caller]) * userRewardPerSecond);
                return reward;
            }
            else {
                reward = ((time - previousStakingRewardClaimTimestamp[_icoStageID][_caller]) * userRewardPerSecond);
                return reward;
            }            
        } else {
            reward = ((stakingEndTime - previousStakingRewardClaimTimestamp[_icoStageID][_caller]) * userRewardPerSecond);
            return reward;
        }
    }

    function getEligibleStakableToken(
        uint256 _icoStageID,
        address _caller
    ) public view returns(uint256) {
        uint256 balance = icoInterface.UserDepositsPerICOStage(_icoStageID, _caller) - totalStakedPerICO[_icoStageID][_caller];
        return balance;
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
            "ex1Staking: Not Staked Yet!"
        );
        isStaked[_icoStageID][_msgSender()] = false;
        unstaked[_icoStageID][_msgSender()] = true;
        unstakeTimestamp[_icoStageID][_msgSender()] = block.timestamp;

        return true;
    }

    function updateIcoInterface( Iex1ICO _icoInterface ) external onlyRole(OWNER_ROLE) {
        icoInterface = _icoInterface;
    }

    function updateVestingInterface( IVestingICO _vestingInterface ) external onlyRole(OWNER_ROLE) {
        vestingInterface = _vestingInterface;
    }

    function updateEX1Token(IERC20 _tokenAddress) external onlyRole(OWNER_ROLE) {
        ex1Token = IERC20(_tokenAddress);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}