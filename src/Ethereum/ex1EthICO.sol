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

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant ICO_AUTHORISER_ROLE = keccak256("ICO_AUTHORISER_ROLE");

    IAggregator public aggregatorInterfaceETH = IAggregator(0x143db3CEEfbdfe5631aDD3E50f7614B6ba708BA7);

    struct ICOStage{
        uint256 startTime;
        uint256 endTime;
        uint256 stageID;
        uint256 tokenPrice;
        bool isActive;
    }

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

    uint256 public MaxTokenLimitPerAddress = 10000000000000 * 10 ** 18;
    uint256 public MaxTokenLimitPerTransaction = 10000000000000 * 10 ** 18;

    uint256 public totalBuyers;
    uint256 public totalETHRaised;
    uint256[] public stageIDs;

    mapping(uint256 => ICOStage) public icoStages;
    mapping(uint256 => uint256) public tokensRaisedPerStage;
    mapping(uint256 => mapping(address => bool)) public HoldersExists; 
    mapping(address => uint256) public HoldersCummulativeBalance;
    mapping(uint256 => mapping(address => uint256)) public UserDepositsPerICOStage;

    address public receivingWallet;


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier checkSaleStatus(uint256 _icoStageID) {
        require(
            block.timestamp >= icoStages[_icoStageID].startTime && 
            block.timestamp <= icoStages[_icoStageID].endTime &&
            icoStages[_icoStageID].isActive,
            "ex1Presale: Sale Not Active!"
        );
        _;
    } 

    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
    }

    function createICOStage(
        uint256 _startTime, 
        uint256 _endTime,
        uint256 _tokenPriceUSD,
        uint256 _icoStageID,
        bool _isActive
    ) external onlyRole(ICO_AUTHORISER_ROLE) {       
        icoStages[_icoStageID] = ICOStage({
            startTime: _startTime,
            endTime: _endTime,
            stageID: _icoStageID,
            tokenPrice: _tokenPriceUSD,
            isActive: _isActive
        });

        stageIDs.push(_icoStageID);

        emit ICOStageCreated(
            _icoStageID,
            _startTime,
            _endTime,
            _tokenPriceUSD,
            _isActive
        );
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
        @dev Function to get the token price in ETH
        @param amount: The amount of tokens
        @param _icoStageID: The ID of the ICO stage
     */
    function getTokenPriceInETH(
        uint256 amount,
        uint256 _icoStageID
    ) public view returns (uint256 ethAmount) {
        uint256 usdPrice = calculatePrice(amount, _icoStageID);
        ethAmount = (usdPrice * (10**18)) / getLatestETHPrice();
        return ethAmount;
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
            _amount < MaxTokenLimitPerTransaction || HoldersCummulativeBalance[msg.sender] < MaxTokenLimitPerAddress,
            "ex1Presale: Max Limit Reached!"
        );
        require(
            icoStages[_icoStageID].isActive,
            "ex1Presale: Stage does not exist or is inactive!"
        );
        uint256 tokenValue = icoStages[_icoStageID].tokenPrice;
        uint256 usdValueUnscaled = ((_amount/(10 ** 18)) * (tokenValue/(10 ** 18)));       
        return usdValueUnscaled;
    }

    function purchasedViaEth(
        uint256 _amount,
        uint256 _icoStageID
    ) external checkSaleStatus(_icoStageID) payable nonReentrant {
        require(
            block.timestamp >= icoStages[_icoStageID].startTime && block.timestamp <= icoStages[_icoStageID].endTime,
            "ex1Presale: Invalid Stage Paramaters"
        );
        uint256 ethAmount = getTokenPriceInETH(_amount, _icoStageID);
        require(
            msg.value >= ethAmount,
            "EthPayment: Insufficient Eths Value signed!"
        );
        tokensRaisedPerStage[_icoStageID] += _amount;
        if (!HoldersExists[_icoStageID][msg.sender]) {
            totalBuyers ++;
            HoldersExists[_icoStageID][msg.sender] = true;
        }
        HoldersCummulativeBalance[msg.sender] += _amount;
        UserDepositsPerICOStage[_icoStageID][msg.sender] += _amount;
        totalETHRaised += ethAmount;
        
        (bool success, ) = payable(receivingWallet).call{value: msg.value}("");
        require(
            success,
            "Ex1 ETH: Transfer of ETH failed"
        );

        emit TokensBoughtETH(
            _msgSender(),
            _amount, 
            icoStages[_icoStageID].tokenPrice, 
            ethAmount, 
            _icoStageID, 
            block.timestamp
        );        
    }

    function setReceiverWallet(address _wallet) external onlyRole(OWNER_ROLE) {
        require(
            _wallet != address(0),
            "ex1Presale: Invalid Wallet Address!"
        );
        receivingWallet = _wallet;
    } 

    function setMaxTokenLimitPerTransaction(
        uint256 _limit
    ) external onlyRole(OWNER_ROLE) {
        MaxTokenLimitPerTransaction = _limit;
    }

    function setMaxTokenLimitPerAddress(
        uint256 _limit
    ) external onlyRole(OWNER_ROLE) {
        MaxTokenLimitPerAddress = _limit;
    }

    function setIAggregatorInterfaceETH(IAggregator _aggregator) external onlyRole(OWNER_ROLE) {
        require(
            address(_aggregator) != address(0),
            "ex1Presale: Invalid Aggregator Address!"
        );
        aggregatorInterfaceETH = _aggregator;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}