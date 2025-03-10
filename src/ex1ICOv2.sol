// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./Interfaces/IAggregator.sol";

contract Ex1ICO is Initializable, ReentrancyGuardUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public ex1Token;

    IERC20 public USDCAddress;
    IERC20 public USDTAddress;

    IAggregator public aggregatorInterfaceETH;
    IAggregator public aggregatorInterfaceBTC;

    bytes32 public constant TXN_RECORDER_ROLE = keccak256("TXN_RECORDER_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant ICO_AUTHORISER_ROLE = keccak256("ICO_AUTHORISER_ROLE");
    
    struct ICOStage{
        uint256 startTime;
        uint256 endTime;
        uint256 stageID;
        uint256 tokenPrice;
        bool isActive;
    }

    uint256 public MaxTokenLimitPerAddress;
    uint256 public MaxTokenLimitPerTransaction;

    uint256 public totalTokensSold;
    uint256 public totalBuyers;
    uint256 public totalUSDRaised;
    uint256 public totalETHRaised;
    uint256 public totalBTCRaised;

    uint256 public latestICOStageID;
    uint256[] public stageIDs;

    mapping(uint256 => ICOStage) public icoStages;

    mapping(uint256 => uint256) public tokensRaisedPerStage;  
    mapping(uint256 => uint256) public usdRaisedPerStage;
    
    mapping(uint256 => mapping(address => uint256)) public UserDepositsPerICOStage; 
    mapping(uint256 => mapping(address => bool)) public HoldersExists;
    mapping(address => uint256) public HoldersCumulativeBalance;

    mapping(address => uint256) public BoughtWithEth;
    mapping(address => uint256) public BoughtWithBTC;

    address public recievingWallet;  
    bool public isTokenReleasable; 

    event TokensBoughtUSD(
        address indexed buyer,
        string tokenAddress,
        uint256 amount,
        uint256 TokenPrice,
        uint256 usdPaid,
        uint256 ICOStage
    );

    event TokensBoughtOffchain(
        address indexed buyer,
        string tokenAddress,
        uint256 amount,
        uint256 TokenPrice,
        uint256 ethPaid,
        uint256 ICOStage
    );

    event ICOStageCreated(
        uint256 stageID,
        uint256 startTime,
        uint256 endTime,
        uint256 tokenPrice,
        bool isActive
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
        _grantRole(ICO_AUTHORISER_ROLE, msg.sender);
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
        if(latestICOStageID >= 1 ) {
            require(
            _startTime > icoStages[latestICOStageID].endTime,
            "ex1Presale: Overlapping start time"
        );
        }        
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

        icoStages[latestICOStageID] = ICOStage({
            startTime: _startTime,
            endTime: _endTime,
            stageID: latestICOStageID,
            tokenPrice: _tokenPriceUSD,
            isActive: _isActive
        });

        stageIDs.push(latestICOStageID);

        emit ICOStageCreated(
            latestICOStageID,
            _startTime,
            _endTime,
            _tokenPriceUSD,
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

    function nextICOStageID() external view returns(uint256) {
        return latestICOStageID + 1;
    }

    /** 
        @dev Function to get the latest current active ICO stage
        @return uint256 The ID of the latest active ICO stage
    */
    function getCurrentOrNextActiveICOStage() external view returns (string memory, uint256) {
        require(latestICOStageID > 0, "ex1: No ICOs Created Yet");

        uint256 nextActiveStageID = latestICOStageID + 1;
        bool nextStageFound = false;

        for (uint _id = 0; _id <= latestICOStageID; _id++) {
            if (
                (block.timestamp > icoStages[_id].startTime) &&
                (block.timestamp < icoStages[_id].endTime) &&
                (icoStages[_id].isActive == true)
            ) {
                return ("Current Stage", _id);
            }
            if (
                !nextStageFound &&
                block.timestamp < icoStages[_id].startTime &&
                icoStages[_id].isActive == true
            ) {
                nextActiveStageID = _id;
                nextStageFound = true;
            }
        }
        if (nextStageFound) {
            return ("Next Active Stage", nextActiveStageID);
        }

        revert("ex1: No Active or Upcoming ICO Stage Found");
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
        uint256 _tokenPriceUSD,
        bool active
    ) external onlyRole(ICO_AUTHORISER_ROLE) {
        require(_stageID <= latestICOStageID, "ex1Presale: Stage does not exist");
        require(
            (_startTime < _endTime) &&
            _endTime > block.timestamp,
            "ex1Presale: Invalid time range!"
        );
        uint256 prevID = _stageID - 1;
        uint256 nextID = _stageID + 1;
        if(_stageID > 1) {
            require(
                _startTime > icoStages[prevID].endTime,
                "ICO: Start Time Overlapping with previous ICO end Time!"
            );                         
        }
        if(_stageID < latestICOStageID) {
            require(
                _endTime < icoStages[nextID].startTime,
                "ICO: End Time Overlapping with next ICO startTime!"
            ); 
        }
        icoStages[_stageID].startTime = _startTime;
        icoStages[_stageID].tokenPrice = _tokenPriceUSD;
        icoStages[_stageID].isActive = active;
        icoStages[_stageID].endTime = _endTime;

        emit ICOStageCreated(_stageID, _startTime, _endTime, _tokenPriceUSD, active);
    }

    /**
         @dev To get latest ETH price in 10**8 format
    **/
    function getLatestETHPrice() public view returns (uint256) {
        (, int256 price, , , ) = aggregatorInterfaceETH.latestRoundData();
        return uint256(price);
    }

    /**
         @dev To get latest BTC price in 10**8 format
    */     
    function getLatestBTCPrice() public view returns (uint256) {
        (, int256 price, , , ) = aggregatorInterfaceBTC.latestRoundData();
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
    ) public view returns (uint256 ethAmount) {
        uint256 usdPrice = calculatePrice(amount, _icoStageID); 
        uint256 latestEthPrice = getLatestETHPrice() * (10 ** 10); 
        uint256 _ethAmount = (usdPrice * (10 ** 18)) / latestEthPrice;   
        return _ethAmount;
    }

    /**
        @dev Function to get the token price in BTC
        @param amount: The amount of tokens
        @param _icoStageID: The ID of the ICO stage
     */
    function getTokenPriceInBTC(
        uint256 amount,
        uint256 _icoStageID
    ) external view returns (uint256 BTCAmount) {
        uint256 usdPrice = calculatePrice(amount, _icoStageID);
        uint256 latestBTCPrice = getLatestBTCPrice() * (10 ** 10);
        uint256 _btcAmount = (usdPrice * (10 ** 18)) / latestBTCPrice;
        return _btcAmount;
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
        uint256 usdValueUnscaled = (_amount * tokenValue)/(10 ** 18);       
        return usdValueUnscaled;
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
        uint256 usdValue = calculatePrice(_amount, _icoStageID);

        string memory USDC = "USDC";
        emit TokensBoughtUSD(
            msg.sender,
            USDC,
            _amount,
            icoStages[_icoStageID].tokenPrice,
            usdValue,
            _icoStageID
        );
        if (isTokenReleasable) {
            IERC20(ex1Token).safeTransfer(msg.sender, _amount); 
        }
        else {
            UserDepositsPerICOStage[_icoStageID][msg.sender] += _amount;
        }
        if (!HoldersExists[_icoStageID][msg.sender]) {
            totalBuyers ++;
            HoldersExists[_icoStageID][msg.sender] = true;
        }
        
        totalTokensSold += _amount;
               
        tokensRaisedPerStage[_icoStageID] += _amount;
        HoldersCumulativeBalance[msg.sender] += _amount;

        totalUSDRaised += usdValue;
        usdRaisedPerStage[_icoStageID] += usdValue;

        IERC20(_token).safeTransferFrom(_msgSender(), recievingWallet, usdValue);
        
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
        uint256 usdValue = calculatePrice(_amount, _icoStageID);

        string memory USDT = "USDT";
        emit TokensBoughtUSD(
            msg.sender,
            USDT,
            _amount,
            icoStages[_icoStageID].tokenPrice,
            usdValue,
            _icoStageID
        );
        if (isTokenReleasable) {
            IERC20(ex1Token).safeTransfer(msg.sender, _amount); 
        }
        else {
            UserDepositsPerICOStage[_icoStageID][msg.sender] += _amount;
        }
        if (!HoldersExists[_icoStageID][msg.sender]) {
            totalBuyers ++;
            HoldersExists[_icoStageID][msg.sender] = true;
        }
        
        totalTokensSold += _amount;
               
        tokensRaisedPerStage[_icoStageID] += _amount;
        HoldersCumulativeBalance[msg.sender] += _amount;

        totalUSDRaised += usdValue;
        usdRaisedPerStage[_icoStageID] += usdValue;
        
        IERC20(_token).safeTransferFrom(_msgSender(), recievingWallet, usdValue);
        
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
    ) external checkSaleStatus(_icoStageID) onlyRole(TXN_RECORDER_ROLE) {       

        totalTokensSold += _amount;
               
        tokensRaisedPerStage[_icoStageID] += _amount;

        if (isTokenReleasable) {
            bool success = IERC20(ex1Token).transfer(_recipient, _amount); 
            require(
                success,
                "ex1Presale: Token Transfer Failed!"
            );
        }
        else {
            UserDepositsPerICOStage[_icoStageID][_recipient] += _amount;
        }

        if (!HoldersExists[_icoStageID][_recipient]) {
            totalBuyers += 1;
            HoldersExists[_icoStageID][_recipient] = true;
        }
        HoldersCumulativeBalance[_recipient] += _amount;

        totalETHRaised += _ethRecieved;

        BoughtWithEth[_recipient] += _ethRecieved;
        string memory ETH = "ETH";

        emit TokensBoughtOffchain(
            _recipient,
            ETH,
            _amount,
            icoStages[_icoStageID].tokenPrice,
            _ethRecieved,
            _icoStageID
        );
    }

    /**
        * @dev Records a transaction for token purchase made using BTC during an ICO stage. 
        * This function is callable only by a backend wallet with the `BTC_TXN_RECORDER_ROLE` 
        * and is triggered when the transaction is recorded on the BTC chain via backend APIs.
        * 
        * @param _amount The number of tokens purchased.
        * @param _btcRecieved The amount of BTC received for the transaction.
        * @param _icoStageID The ID of the ICO stage for which the purchase is being recorded.
        * @param _recipient The address of the buyer receiving the tokens.
    */
    function purchasedViaBTC(
        uint256 _amount,   
        uint256 _btcRecieved, 
        uint256 _icoStageID, 
        address _recipient 
    ) external checkSaleStatus(_icoStageID) onlyRole(TXN_RECORDER_ROLE) {       

        totalTokensSold += _amount;
               
        tokensRaisedPerStage[_icoStageID] += _amount;

        if (isTokenReleasable) {
            bool success = IERC20(ex1Token).transfer(_recipient, _amount); 
            require(
                success,
                "ex1Presale: Token Transfer Failed!"
            );
        }
        else {
            UserDepositsPerICOStage[_icoStageID][_recipient] += _amount;
        }

        if (!HoldersExists[_icoStageID][_recipient]) {
            totalBuyers += 1;
            HoldersExists[_icoStageID][_recipient] = true;
        }
        HoldersCumulativeBalance[_recipient] += _amount;

        totalBTCRaised += _btcRecieved;

        BoughtWithBTC[_recipient] += _btcRecieved;

        string memory BTC = "BTC";

        emit TokensBoughtOffchain(
            _recipient,
            BTC,
            _amount,
            icoStages[_icoStageID].tokenPrice,
            _btcRecieved,
            _icoStageID
        );
    }

    /////Set Functions//////////

    function setMaxTokenLimitPerAddress(
        uint256 _limit
    ) external onlyRole(OWNER_ROLE) {
        MaxTokenLimitPerAddress = _limit;
    }

    function setTokenSaleAddress(
        IERC20 _ex1Token
    ) external onlyRole(OWNER_ROLE) {
        ex1Token = _ex1Token;
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