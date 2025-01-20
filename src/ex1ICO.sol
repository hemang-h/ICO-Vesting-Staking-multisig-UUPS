// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface IAggregator {
    function latestRoundData()
    external 
    view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

contract Ex1ICO is Initializable, ReentrancyGuardUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public ex1Token;

    IERC20 public USDCAddress = IERC20(0x3966d24Aa915f316Fb3Ae8b7819EA1920c78615E); 
    IERC20 public USDTAddress = IERC20(0x69AFebb38Dc509aaD0a0dde212e03e4D22D581d1);

    IAggregator public aggregatorInterfaceETH = IAggregator(0x143db3CEEfbdfe5631aDD3E50f7614B6ba708BA7);
    IAggregator public aggregatorInterfaceBTC = IAggregator(0x5741306c21795FdCBb9b265Ea0255F499DFe515C);

    bytes32 public constant ETH_TXN_RECORDER_ROLE = keccak256("ETH_TXN_RECORDER_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant ICO_AUTHORISER_ROLE = keccak256("ICO_AUTHORISER_ROLE");
    bytes32 public constant VESTING_AUTHORISER_ROLE = keccak256("VESTING_AUTHORISER_ROLE");
    bytes32 public constant STAKING_AUTHORISER_ROLE = keccak256("STAKING_AUTHORISER_ROLE"); 

    struct ICOStage{
        uint256 startTime;
        uint256 endTime;
        uint256 stageID;
        uint256 tokenPrice;
        bool isActive;
    }

    struct claimSchedule {
        uint256 icoStageID;
        uint256 startTime;
        uint256 endTime;
        uint256 interval;
        uint256 slicePeriod;
    }

    struct StakingParamter {
        uint256 percentageReturn;
        uint256 timePeriodInSeconds;
        uint256 _icoStageID;
        uint256 _stakingEndTime;
    }

    uint256 public MaxTokenLimitPerAddress = 10000000000000 * 10 ** 18;
    uint256 public MaxTokenLimitPerTransaction = 10000000000000 * 10 ** 18;

    uint256 public totalTokensSold;
    uint256 public totalBuyers;
    uint256 public totalUSDRaised;
    uint256 public totalETHRaised;

    uint256 public latestICOStageID;
    uint256[] private stageIDs;

    mapping(address => uint256) public HoldersCumulativeBalance;
    mapping(address => bool) public HoldersExists;
    mapping (uint256 => uint256) public tokensRaisedPerStage;  

    mapping(address => bool) public isClaimed; 
    mapping(address => uint256) public prevClaimTimestamp;
    
    mapping(uint256 => mapping(address => uint256)) public UserDepositsPerICOStage; 
    mapping(uint256 => mapping(address => uint256)) public UserClaimedPerICOStage;
    mapping(uint256 => mapping(address => uint256)) public claimedAmount;

    mapping(address => uint256) public BoughtWithEth;

    mapping(uint256 => ICOStage) public icoStages;
    mapping(uint256 => claimSchedule) public claimSchedules;
    mapping(uint256 => StakingParamter) public stakingParameters;

    mapping(uint256 => mapping(address => bool)) public isStaked;
    mapping(uint256 => mapping(address => uint256)) public stakeTimestamp;
    mapping(uint256 => mapping(address => uint256)) public previousStakingRewardClaimTimestamp;

    address public recievingWallet;    
    bool public isTokenReleasable; 

    event TokensBoughtUSDT(
        address indexed buyer,
        uint256 amount,
        uint256 TokenPrice,
        uint256 usdtPaid,
        uint256 ICOStage,
        uint256 timestamp
    );

    event TokensBoughtUSDC(
        address indexed buyer,
        uint256 amount,
        uint256 TokenPrice,
        uint256 usdcPaid,
        uint256 ICOStage,
        uint256 timestamp
    );

    event TokensBoughtETH(
        address indexed buyer,
        uint256 amount,
        uint256 TokenPrice,
        uint256 ethPaid,
        uint256 ICOStage,
        uint256 timestamp
    );

    event ICOStageCreated(
        uint256 stageID,
        uint256 startTime,
        uint256 endTime,
        uint256 tokenPrice,
        bool isActive
    );

    event ICOStageUpdated(
        uint256 stageID,
        uint256 startTime,
        uint256 endTime,
        uint256 tokenPrice
    );

    event ClaimScheduleCreated(
        uint256 indexed icoStageID,
        uint256 startTime,
        uint256 endTime,
        uint256 interval,
        uint256 slicePeriod,
        uint256 timestamp
    );

    event StakingRewardClaimed(
        address indexed staker,
        uint256 amount,
        uint256 timestamp
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _ex1Token) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        
        ex1Token = IERC20(_ex1Token);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    /** 
        @dev Modifier to check if the sale is active
    */
    modifier checkSaleStatus(uint256 _icoStageID) {
        require(
            block.timestamp >= icoStages[_icoStageID].startTime && 
            block.timestamp <= icoStages[_icoStageID].endTime &&
            icoStages[_icoStageID].isActive,
            "ex1Presale: Sale Not Active!"
        );
        _;
    } 

    /////////////////////////////////////////////////////////
    ////////////////////  ICO STAGES  ///////////////////////
    ////////////////////////////////////////////////////////
    /** 
        * @dev Function to create a new ICO stage
        * @param _startTime: The start time of the ICO stage in unix timestamp
        * @param _endTime: The end time of the ICO stage in unix timestamp
        * @param _tokenPriceUSD: The price of the token in USD
        * @param _isActive: The status of the ICO stage (active or inactive)
    */
    function createICOStage(
        uint256 _startTime, 
        uint256 _endTime,
        uint256 _tokenPriceUSD,
        bool _isActive
    ) external onlyRole(ICO_AUTHORISER_ROLE) {
        require (
            (_startTime < _endTime) && (_startTime > 0 || _endTime > 0),
            "ex1Presale: Invalid Schedule or Parameters!"
        );
        require (
            _startTime > block.timestamp,
            "ex1Presale: Invalid Start Time!" 
        );
        require (
            _endTime > block.timestamp,
            "ex1Presale: Invalid End Time!"
        );
        latestICOStageID ++;
        uint256 _scaledTokenPrice = (_tokenPriceUSD * 1e18) / 1e10;

        icoStages[latestICOStageID] = ICOStage({
            startTime: _startTime,
            endTime: _endTime,
            stageID: latestICOStageID,
            tokenPrice: _scaledTokenPrice,
            isActive: _isActive
        });

        stageIDs.push(latestICOStageID);

        emit ICOStageCreated(
            latestICOStageID,
            _startTime,
            _endTime,
            _scaledTokenPrice,
            _isActive
        );
    }

    /** 
        @dev Function to get all ICO stages
    */
    function getAllICOStages() external view returns (ICOStage[] memory) {
        ICOStage[] memory stages = new ICOStage[](stageIDs.length);
        for (uint256 i = 0; i < stageIDs.length; i++) {
            stages[i] = icoStages[stageIDs[i]];
        }
        return stages;
    }

    /** 
        @dev Function to deactivate a specific ICO stage
    */
    function deactivateICOStage(uint256 _stageID) external onlyRole(ICO_AUTHORISER_ROLE) {
        require(icoStages[_stageID].isActive, "Stage is already inactive!");
        icoStages[_stageID].isActive = false;
    }

    /** 
        @dev Function to update a specific ICO stage
        @param _stageID: The ID of the ICO stage that needs to be updated
        @param _startTime: The new start time of the ICO stage in unix timestamp
        @param _endTime: The new end time of the ICO stage in unix timestamp
        @param _tokenPriceUSD: The new price of the token in USD
    */
    function updateICOStage(
        uint256 _stageID,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _tokenPriceUSD
    ) external onlyRole(ICO_AUTHORISER_ROLE) {
        require(icoStages[_stageID].isActive, "ex1Presale: Stage does not exist or is inactive!");
        require(
            (_startTime < _endTime) &&
            _endTime > block.timestamp,
            "ex1Presale: Invalid time range!"
        );

        icoStages[_stageID].startTime = _startTime;
        icoStages[_stageID].endTime = _endTime;
        icoStages[_stageID].tokenPrice = _tokenPriceUSD;

        emit ICOStageUpdated(_stageID, _startTime, _endTime, _tokenPriceUSD);
    }

    /**
         @dev To get latest ETH price in 10**8 format
    **/
    function getLatestETHPrice() public view returns (uint256) {
        (, int256 price, , , ) = aggregatorInterfaceETH.latestRoundData();
        price = (price * (10 ** 8));
        return uint256(price);
    }

    /**
         @dev To get latest BTC price in 10**8 format
    */     
    function getLatestBTCPrice() public view returns (uint256) {
        (, int256 price, , , ) = aggregatorInterfaceBTC.latestRoundData();
        price = (price * (10 ** 8));
        return uint256(price);
    }

    /**
        @dev Function to get the token price in ETH
        @param amount: The amount of tokens
        @param _icoStageID: The ID of the ICO stage
     */
    function getTokenPriceInETH(
        uint256 amount,
        uint256 _icoStageID
    ) external view returns (uint256 ethAmount) {
        uint256 usdPrice = calculatePrice(amount, _icoStageID);
        ethAmount = (usdPrice * (10**18)) / getLatestETHPrice();
        return ethAmount;
    }

    /**
        @dev Function to get the token price in BTC
        @param amount: The amount of tokens
        @param _icoStageID: The ID of the ICO stage
     */
    function geTokenPriceInBTC(
        uint256 amount,
        uint256 _icoStageID
    ) external view returns (uint256 BTCAmount) {
        uint256 usdPrice = calculatePrice(amount, _icoStageID);
        BTCAmount = (usdPrice * (10**18)) / getLatestBTCPrice();
        return BTCAmount;
    }

    /**
        @dev Calculates the price of a specified amount of tokens in USD for a given ICO stage.
        @param _amount The number of tokens for which the price needs to be calculated.
        @param _icoStageID The ID of the ICO stage to fetch the token price.
        @return The USD value of the specified amount of tokens, considering the token price at the specified ICO stage.
    */
    function calculatePrice(
        uint256 _amount,
        uint256 _icoStageID
    ) public view returns(uint256) {
         require (
            _amount < MaxTokenLimitPerTransaction || HoldersCumulativeBalance[msg.sender] < MaxTokenLimitPerAddress,
            "ex1Presale: Max Limit Reached!"
        );
        require(
            icoStages[_icoStageID].isActive,
            "ex1Presale: Stage does not exist or is inactive!"
        );
        uint256 tokenValue = icoStages[_icoStageID].tokenPrice;
        uint256 usdValue = (_amount * tokenValue)/(10 ** 18);       
        return usdValue;
    }
   
   /**
        @dev Function to buy tokens with USDC
        @param _amount: The amount of tokens to buy
        @param _icoStageID: The ID of the ICO stage
        @param _token: The token address using which the purchase is made
    */
    function buyWithUSDC(
        uint256 _amount,
        uint256 _icoStageID,
        IERC20 _token
    ) external checkSaleStatus(_icoStageID) returns(bool) {
        require(
            _token == USDCAddress,
            "ex1Sale: Token Invalid!"
        );
        require(
            block.timestamp >= icoStages[_icoStageID].startTime && block.timestamp <= icoStages[_icoStageID].endTime,
            "ex1Presale: Invalid Stage Paramaters"
        );
        uint256 price = calculatePrice(_amount, _icoStageID);
        uint256 usdValue = price/(10 ** 12);

        emit TokensBoughtUSDC(
            msg.sender,
            _amount,
            icoStages[_icoStageID].tokenPrice,
            usdValue,
            _icoStageID,
            block.timestamp
        );
        if (isTokenReleasable) {
            ex1Token.safeTransfer(msg.sender, _amount); 
        }
        else {
            UserDepositsPerICOStage[_icoStageID][msg.sender] += _amount;
        }
        if (!HoldersExists[msg.sender]) {
            totalBuyers ++;
            HoldersExists[msg.sender] = true;
        }
        
        totalTokensSold += _amount;
               
        tokensRaisedPerStage[_icoStageID] += _amount;
        HoldersCumulativeBalance[msg.sender] += _amount;

        totalUSDRaised += usdValue;

        sendToWallet(usdValue, _token);
        
        return true;
    }

    /**
        @dev Function to buy tokens with USDT
    */
    function buyWithUSDT(
        uint256 _amount,
        uint256 _icoStageID,
        IERC20 _token
    ) external checkSaleStatus(_icoStageID) returns(bool) {
        require(
            _token == USDTAddress,
            "ex1Sale: Token Invalid!"
        );
        require(
            block.timestamp >= icoStages[_icoStageID].startTime && block.timestamp <= icoStages[_icoStageID].endTime,
            "ex1Presale: Invalid Stage Paramaters"
        );
        uint256 price = calculatePrice(_amount, _icoStageID);
        uint256 usdValue = price/(10 ** 12);

        emit TokensBoughtUSDT(
            msg.sender,
            _amount,
            icoStages[_icoStageID].tokenPrice,
            usdValue,
            _icoStageID,
            block.timestamp
        );
        if (isTokenReleasable) {
            bool success = IERC20(ex1Token).transfer(msg.sender, _amount); 
            require(
                success,
                "ex1Presale: Token Transfer Failed!"
            );
        }
        else {
            UserDepositsPerICOStage[_icoStageID][msg.sender] += _amount;
        }
        if (!HoldersExists[msg.sender]) {
            totalBuyers ++;
            HoldersExists[msg.sender] = true;
        }
        
        totalTokensSold += _amount;
               
        tokensRaisedPerStage[_icoStageID] += _amount;
        HoldersCumulativeBalance[msg.sender] += _amount;

        totalUSDRaised += usdValue;

        sendToWallet(usdValue, _token);
        
        return true;
    }

    /**
        * @dev Records a transaction for token purchase made using ETH during an ICO stage. 
        * This function is callable only by a backend wallet with the `ETH_TXN_RECORDER_ROLE` 
        * and is triggered when the transaction is recorded on the Ethereum chain via backend APIs.
        * 
        * @param _amount The number of tokens purchased.
        * @param _ethRecieved The amount of ETH received for the transaction.
        * @param _icoStageID The ID of the ICO stage for which the purchase is being recorded.
        * @param _recipient The address of the buyer receiving the tokens.
    */
    function purchasedViaEth(
        uint256 _amount,   
        uint256 _ethRecieved, 
        uint256 _icoStageID, 
        address _recipient 
    ) external checkSaleStatus(_icoStageID) onlyRole(ETH_TXN_RECORDER_ROLE) {       

        totalTokensSold += _amount;
               
        tokensRaisedPerStage[_icoStageID] += _amount;

        if (isTokenReleasable) {
            bool success = IERC20(ex1Token).transfer(_recipient, _amount*(10 ** 18)); 
            require(
                success,
                "ex1Presale: Token Transfer Failed!"
            );
        }
        else {
            UserDepositsPerICOStage[_icoStageID][_recipient] += _amount;
        }

        if (!HoldersExists[_recipient]) {
            totalBuyers += 1;
            HoldersExists[_recipient] = true;
        }
        HoldersCumulativeBalance[_recipient] += _amount;

        totalETHRaised += _ethRecieved;

        BoughtWithEth[_recipient] += _ethRecieved;

        emit TokensBoughtETH(
            _recipient,
            _amount,
            icoStages[_icoStageID].tokenPrice,
            _ethRecieved,
            _icoStageID,
            block.timestamp
        );
    }

    function sendToWallet(uint256 _raise, IERC20 _token) internal {
        (bool success, ) = address(_token).call(
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    _msgSender(),
                    recievingWallet,
                    _raise
                )
            );
            require(success, "Token payment failed");
    }
    // ////////////////////////////////////////////////////////////////
    // ///////////////////  CLAIM FUNCTIONS   ////////////////////////
    // //////////////////////////////////////////////////////////////
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
        require(
            _startTime > icoStages[_icoStageID].endTime, 
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
    */
    function claimTokens(
        uint256 _icoStageID
    ) external nonReentrant returns(bool) {
        require(
            block.timestamp >= claimSchedules[_icoStageID].startTime 
            && block.timestamp <= claimSchedules[_icoStageID].endTime,
            "ex1Presale: Claim Not Active!"
        );
        require(
            UserDepositsPerICOStage[_icoStageID][_msgSender()] > 0,
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

        uint256 totalDeposits = UserClaimedPerICOStage[_icoStageID][_caller];
        uint256 totalNumberOfSlices = (schedule.endTime - schedule.endTime) / schedule.slicePeriod;
        uint256 tokenPerSlice = totalDeposits / totalNumberOfSlices;

        uint256 elapsedSlices = (block.timestamp - schedule.startTime) / schedule.slicePeriod;
        uint256 claimable = tokenPerSlice * elapsedSlices - claimedAmount[_icoStageID][msg.sender];

        return claimable;
    } 

    //////////////////////////////////////////////////////////////////
    ////////////////////   STAKING FUNCTIONS   //////////////////////
    ////////////////////////////////////////////////////////////////
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
        require(
            _percentageReturn > 0 && _percentageReturn <= 100,
            "ex1Presale: Invalid Percentage!"
        );
        require(
            _timePeriodInSeconds > 0,
            "ex1Presale: Invalid Time Period!"
        );
        require(
            claimSchedules[_icoStageID].startTime > block.timestamp,
            "ex1Presale: Vesting Schedule Claiming already Initiated"
        );
        stakingParameters[_icoStageID] = StakingParamter({
            percentageReturn: _percentageReturn,
            timePeriodInSeconds: _timePeriodInSeconds,
            _icoStageID: _icoStageID,
            _stakingEndTime: claimSchedules[_icoStageID].startTime - 1
        });
    }

    /**
        @dev Function to stake tokens
        @param _icoStageID: The ID of the ICO stage
    */
    function stake(
        uint256 _icoStageID
    ) external returns(bool) {
        require(
            UserDepositsPerICOStage[_icoStageID][_msgSender()] > 0,
            "ex1Presale: No Tokens to Stake!"
        );
        require(
            block.timestamp <= claimSchedules[_icoStageID].startTime,
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
        uint256 userPercentage = (UserDepositsPerICOStage[_icoStageID][_caller] * (stakingParameters[_icoStageID].percentageReturn)) / 100;
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
        uint256 userPercentage = UserDepositsPerICOStage[_icoStageID][_caller] * (stakingParameters[_icoStageID].percentageReturn / 100);
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

    /////Set Functions//////////

    function setMaxTokenLimitPerAddress(
        uint256 _limit
    ) external onlyRole(OWNER_ROLE) {
        MaxTokenLimitPerAddress = _limit;
    }

    function setMaxTokenLimitPerTransaction(
        uint256 _limit
    ) external onlyRole(OWNER_ROLE) {
        MaxTokenLimitPerTransaction = _limit;
    }

    function setReceiverWallet(address _wallets) external onlyRole(OWNER_ROLE) {
        require(
            _wallets != address(0),
            "ex1Presale: Invalid Wallet Address!"
        );
        recievingWallet = _wallets;
    }    

    function setTokenReleasable() external onlyRole(OWNER_ROLE) {
        isTokenReleasable = !isTokenReleasable;
    }

    function setIAggregatorInterfaceETH(IAggregator _aggregator) external onlyRole(OWNER_ROLE) {
        require(
            address(_aggregator) != address(0),
            "ex1Presale: Invalid Aggregator Address!"
        );
        aggregatorInterfaceETH = _aggregator;
    }

    function setIAggregatorInterfaceBTC(IAggregator _aggregator) external onlyRole(OWNER_ROLE) {
        require(
            address(_aggregator) != address(0),
            "ex1Presale: Invalid Aggregator Address!"
        );
        aggregatorInterfaceBTC = _aggregator;
    }

    function setUSDTAddress(IERC20 _USDTTokenAddress) external onlyRole(OWNER_ROLE) {
        require(
            address(_USDTTokenAddress) != address(0),
            "EX1Presale: Invalid USDT Address!"
        );
        USDTAddress = _USDTTokenAddress;
    }

    function setUSDCAddress(IERC20 _USDCTokenAddress) external onlyRole(OWNER_ROLE) {
        require(
            address(_USDCTokenAddress) != address(0),
            "EX1Presale: Invalid USDC Address!"
        );
        USDCAddress = _USDCTokenAddress;
    }

    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = ex1Token.balanceOf(address(this));
        ex1Token.safeTransfer(recievingWallet, balance);
    }
}


