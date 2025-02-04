// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title PrivateVesting
 * @dev A contract for managing token vesting schedules with role-based access control.
 * It allows creating, updating, and revoking vesting schedules, as well as claiming vested tokens.
 */
contract PrivateVesting is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public ex1Token;
    
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant VESTING_CREATOR_ROLE = keccak256("VESTING_CREATOR_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    
    /**
     * @dev Struct representing a vesting schedule.
     * @param beneficiary The address of the beneficiary.
     * @param vestingScheduleID The unique identifier for the vesting schedule.
     * @param totalAmount The total amount of tokens to be vested.
     * @param startTime The start time of the vesting schedule.
     * @param endTime The end time of the vesting schedule.
     * @param claimInterval The interval between token claims.
     * @param cliffPeriod The cliff period before vesting starts.
     * @param slicePeriod The slice period for calculating vested amounts.
     * @param releasedAmount The amount of tokens already released.
     * @param isRevocable Whether the vesting schedule is revocable.
     * @param isRevoked Whether the vesting schedule has been revoked.
     */
    struct VestingSchedule {
        address beneficiary;
        uint256 vestingScheduleID;
        uint256 totalAmount;
        uint256 startTime;
        uint256 endTime;
        uint256 claimInterval;
        uint256 cliffPeriod;
        uint256 slicePeriod;
        uint256 releasedAmount;
        bool isRevocable;
        bool isRevoked;
    }

    /// @dev Mapping from vesting schedule ID to VestingSchedule.
    mapping(uint256 => VestingSchedule) public vestingSchedules;

    /// @dev Mapping from vesting schedule ID to the last claimed timestamp.
    mapping(uint256 => uint256) public lastClaimedTimestamp;

    /// @dev Mapping from vesting schedule ID to beneficiary address to the last claimed amount.
    mapping(uint256 => mapping(address => uint256)) lastClaimedAmount;

    /// @dev The latest vesting schedule ID.
    uint256 public latestVestingScheduleID;

    uint256[] public scheduleIDs;



    event VestingScheduleCreated(
        address beneficiary,
        uint256 vestingScheduleID,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime,
        uint256 claimInterval,
        uint256 cliffPeriod,
        uint256 slicePeriod,
        uint256 releasedAmount,
        bool isRevocable,
        bool isRevoked
    );
    event VestingScheduleRevoked(
        uint256 vestingScheduleID,
        uint256 timestamp
    );
    event TokensClaimed(
        address beneficiary, 
        uint256 amount,
        uint256 timestamp
    );
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Modifier to check if the vesting schedule ID is valid.
     * @param _vestingScheduleID The ID of the vesting schedule.
     */
    modifier onlyValidSchedule(uint256 _vestingScheduleID) {
        require(_vestingScheduleID > 0 && _vestingScheduleID <= latestVestingScheduleID, "Invalid schedule ID");
        _;
    }

    /**
     * @dev Modifier to check if the vesting schedule is not revoked.
     * @param _vestingScheduleID The ID of the vesting schedule.
     */
    modifier notRevoked(uint256 _vestingScheduleID) {
        require(!vestingSchedules[_vestingScheduleID].isRevoked, "Schedule is revoked");
        _;
    }

    /**
     * @dev Initializes the contract, setting up roles and initializing base contracts.
     */
    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(VESTING_CREATOR_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        ex1Token = IERC20(0x000e49F0741609f4DC7f9641BB6c1F009c984A60);
    }

    /**
     * @dev Sets a new vesting schedule.
     * @param _beneficiary The address of the beneficiary.
     * @param _totalAmount The total amount of tokens to be vested.
     * @param _startTime The start time of the vesting schedule.
     * @param _endTime The end time of the vesting schedule.
     * @param _claimInterval The interval between token claims.
     * @param _cliffPeriod The cliff period before vesting starts.
     * @param _slicePeriod The slice period for calculating vested amounts.
     * @param _isRevocable Whether the vesting schedule is revocable.
     */
    function setVestingSchedule(
        address _beneficiary,
        uint256 _totalAmount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _claimInterval,
        uint256 _cliffPeriod,
        uint256 _slicePeriod,
        bool _isRevocable
    ) external onlyRole(VESTING_CREATOR_ROLE) {
        require(
            _startTime > 0
            && _endTime > 0 
            && _totalAmount > 0
            && _beneficiary != address(0),
            "PrivateVesting: Value cannot be 0 or 0 address!"
        );
        require(
            _endTime > _startTime
            && _startTime > block.timestamp,
            "Private: Invalid Time Schedule"
        );
        require(
            _cliffPeriod > _startTime
            && _cliffPeriod < _endTime,
            "PrivateVesting: Invalid Cliff Period"
        );
        require(
            _claimInterval <= (_endTime - _cliffPeriod)
            && _claimInterval > 0, 
            "Private: Invalid Claim Interval"
        );
        require(
            _slicePeriod >= 0 && _slicePeriod <= 60,
            "PrivateVesting: Invalid Slice Period"
        );
        latestVestingScheduleID ++;

        vestingSchedules[latestVestingScheduleID] = VestingSchedule({
            beneficiary: _beneficiary,
            vestingScheduleID: latestVestingScheduleID,
            totalAmount: _totalAmount,
            startTime: _startTime,
            endTime: _endTime,
            claimInterval: _claimInterval,
            cliffPeriod: _cliffPeriod,
            slicePeriod: _slicePeriod,
            releasedAmount: 0,
            isRevocable: _isRevocable,
            isRevoked: false
        });

        scheduleIDs.push(latestVestingScheduleID);
        
        emit VestingScheduleCreated(
            _beneficiary, 
            latestVestingScheduleID, 
            _totalAmount, 
            _startTime, 
            _endTime, 
            _claimInterval, 
            _cliffPeriod,
            _slicePeriod,
            0,
            _isRevocable,
            false
        );
    }

    /**
     * @dev Updates an existing vesting schedule.
     * @param _vestingScheduleID The ID of the vesting schedule to update.
     * @param _beneficiary The new beneficiary address.
     * @param _totalAmount The new total amount of tokens to be vested.
     * @param _startTime The new start time of the vesting schedule.
     * @param _endTime The new end time of the vesting schedule.
     * @param _claimInterval The new interval between token claims.
     * @param _cliffPeriod The new cliff period before vesting starts.
     * @param _slicePeriod The new slice period for calculating vested amounts.
     */
    function updateVesting(
        uint256 _vestingScheduleID,
        address _beneficiary,
        uint256 _totalAmount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _claimInterval,
        uint256 _cliffPeriod,
        uint256 _slicePeriod
    ) external onlyValidSchedule(_vestingScheduleID) onlyRole(VESTING_CREATOR_ROLE){
        VestingSchedule storage schedule = vestingSchedules[_vestingScheduleID];

        if(block.timestamp > schedule.startTime) {
            require(
                _startTime == schedule.startTime,
                "PrivateVesting: Claim Schedule Already Started!"
            );
        }
        require(
            (_endTime > _startTime) &&
            (_startTime > 0 && _endTime > 0) &&
            (_endTime > block.timestamp) &&
            (_totalAmount > 0),
            "PrivateVesting: Invalid Schedule or Parameters!"
        );
        require(
            _cliffPeriod > _startTime
            && _cliffPeriod < _endTime,
            "PrivateVesting: Invalid Cliff Period"
        );
        require(
            _claimInterval <= (_endTime - _startTime),
            "PrivateVesting: Invalid Cliff Period"
        );
        require(
            _slicePeriod >= 0 && _slicePeriod <= 60,
            "PrivateVesting: Invalid Slice Period"
        );
        schedule.beneficiary = _beneficiary;
        schedule.totalAmount = _totalAmount;
        schedule.claimInterval = _claimInterval;
        schedule.endTime = _endTime;
        schedule.startTime = _startTime;
        schedule.slicePeriod = _slicePeriod;
        schedule.cliffPeriod = _cliffPeriod;
    }

    /**
     * @dev Allows the beneficiary to claim vested tokens.
     * @param _vestingScheduleID The ID of the vesting schedule.
     */
    function claimTokens(uint256 _vestingScheduleID) 
        external 
        nonReentrant 
        onlyValidSchedule(_vestingScheduleID)
        notRevoked(_vestingScheduleID)
    {
        VestingSchedule storage schedule = vestingSchedules[_vestingScheduleID];
        require(_msgSender() == schedule.beneficiary, "Not beneficiary");
        require(block.timestamp > schedule.cliffPeriod, "PrivateVesting: Cliff Period Not ended");
        require(
            block.timestamp - lastClaimedTimestamp[_vestingScheduleID] >= schedule.claimInterval,
            "PrivateVesting: Claim Interval Not reached"
        );
        require(
            schedule.releasedAmount <= schedule.totalAmount, 
            "PrivateVesting: No amount left to Claim"
        );
        
        uint256 claimableAmount = calculateClaimableAmount(_vestingScheduleID);
        require(claimableAmount > 0, "No tokens to claim");
        
        schedule.releasedAmount += claimableAmount;

        lastClaimedAmount[_vestingScheduleID][_msgSender()] = claimableAmount;        
        lastClaimedTimestamp[_vestingScheduleID] = block.timestamp;

        require(ex1Token.transfer(_msgSender(), claimableAmount), "Transfer failed");
        
        emit TokensClaimed(_msgSender(), claimableAmount, block.timestamp);
    } 

    /**
     * @dev Calculates the claimable amount of tokens for a given vesting schedule.
     * @param _vestingScheduleID The ID of the vesting schedule.
     * @return The amount of tokens that can be claimed.
     */
    function calculateClaimableAmount(uint256 _vestingScheduleID) 
        public view 
        returns(uint256) 
    {
        VestingSchedule storage schedule = vestingSchedules[_vestingScheduleID];
        
        if(block.timestamp < schedule.startTime) {
            return 0;
        }
        if(block.timestamp > schedule.endTime) {
            uint256 balance = schedule.totalAmount - schedule.releasedAmount;
            return balance;
        }
        uint256 totalNumberOfSlices = (schedule.endTime - schedule.startTime) / schedule.slicePeriod;
        uint256 tokenPerSlice = schedule.totalAmount / totalNumberOfSlices;

        uint256 elapsedSlices;
        if(lastClaimedTimestamp[_vestingScheduleID] == 0) {
            elapsedSlices = (block.timestamp - schedule.startTime) / schedule.slicePeriod;
        }
        else {
            elapsedSlices = (block.timestamp - lastClaimedTimestamp[_vestingScheduleID])/ schedule.slicePeriod;
        }
        uint256 claimable = tokenPerSlice * elapsedSlices - schedule.releasedAmount;
        return claimable;
    }

    /**
     * @dev Revokes a vesting schedule.
     * @param _vestingScheduleID The ID of the vesting schedule to revoke.
     */
    function revokeSchedule(uint256 _vestingScheduleID) 
        external 
        onlyRole(OWNER_ROLE) 
        onlyValidSchedule(_vestingScheduleID)
        notRevoked(_vestingScheduleID)
    {
        VestingSchedule storage schedule = vestingSchedules[_vestingScheduleID];
        require(schedule.isRevocable, "Schedule is not revocable");
        
        uint256 claimableAmount = calculateClaimableAmount(_vestingScheduleID);
        if (claimableAmount > 0) {
            schedule.releasedAmount += claimableAmount;
            require(ex1Token.transfer(schedule.beneficiary, claimableAmount), "Transfer failed");
            emit TokensClaimed(schedule.beneficiary, claimableAmount, block.timestamp);
        }
        
        schedule.isRevoked = true;
        emit VestingScheduleRevoked(_vestingScheduleID, block.timestamp);
    }

    /**
     * @dev Returns the next claim time for a given vesting schedule.
     * @param _vestingScheduleID The ID of the vesting schedule.
     * @return The next claim time.
     */
    function nextClaimTime(
        uint256 _vestingScheduleID
    ) public view onlyValidSchedule(_vestingScheduleID) returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[_vestingScheduleID];

        require(
            schedule.releasedAmount > 0,
            "ex1Presale: No Tokens to Claim!"
        );
        if(getBalanceLeftToClaim(_vestingScheduleID) == 0) {
            return 0;
        }
        if (block.timestamp < schedule.startTime) {
            return schedule.startTime;
        } else if (
            block.timestamp > schedule.startTime &&
            lastClaimedTimestamp[_vestingScheduleID] == 0
        ) {
            return block.timestamp;
        } else {
            return lastClaimedTimestamp[_vestingScheduleID] + schedule.claimInterval;
        }
    }

    /**
     * @dev Returns the remaining balance of tokens to be claimed for a given vesting schedule.
     * @param _vestingScheduleID The ID of the vesting schedule.
     * @return The remaining balance of tokens.
     */
    function getBalanceLeftToClaim(uint256 _vestingScheduleID) public view returns(uint256) {
        VestingSchedule memory schedule = vestingSchedules[_vestingScheduleID];
        uint256 balance = schedule.totalAmount - schedule.releasedAmount;
        return balance;
    }

    function getAllVestingSchedules() public view returns(VestingSchedule[] memory) {
        VestingSchedule[] memory schedule = new VestingSchedule[](scheduleIDs.length);
        for(uint256 i = 0; i < scheduleIDs.length; i++) {
            schedule[i] = vestingSchedules[scheduleIDs[i]];
        }
        return schedule;
    }

    /**
     * @dev Sets the ERC20 token address for vesting.
     * @param _tokenAddress The address of the ERC20 token.
     */
    function setEx1TokenSaleContract(IERC20 _tokenAddress) external onlyRole(OWNER_ROLE) {
        ex1Token = IERC20(_tokenAddress);
    }

    /**
     * @dev Authorizes an upgrade to a new implementation.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}