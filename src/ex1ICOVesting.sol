// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./Interfaces/InterfaceEx1ICO.sol";

contract ICOVesting is Initializable, ReentrancyGuardUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    Iex1ICO public icoInterface = Iex1ICO(0x301Cc53ff52Bf79C15249fa25d1e8aE8e222F205);
    IERC20 public ex1Token;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant VESTING_AUTHORISER_ROLE = keccak256("VESTING_AUTHORISER_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    uint256 public requiredConfirmations;
    uint256 public proposalCount;

    enum ProposalType{
        SetClaimSchedule,
        UpdateClaimSchedule,
        UpdateInterface,
        UpgradeContract,
        UpdateRequiredConfirmations
    }
   
    struct Proposal{
        mapping(address => bool) hasApproved;
        ProposalType proposalType;
        bytes32 proposalHash;
        bytes paramsData;
        uint256 timestamp;
        uint256 proposalID;
        uint256 approvalCounts;
        bool executed;
    }
    struct ClaimScheduleParam{
        uint256 icoStageID;
        uint256 startTime;
        uint256 endTime;
        uint256 claimInterval;
        uint256 slicePeriod;
    }   
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
    mapping(uint256 => Proposal) public proposals;

    event ClaimScheduleCreated(
        uint256 indexed icoStageID,
        uint256 startTime,
        uint256 endTime,
        uint256 interval,
        uint256 slicePeriod,
        uint256 timestamp
    );
    event ProposalCreated(
        uint256 indexed proposalID,
        ProposalType proposalType,
        bytes32 proposalHash
    );
    event ProposalApproved(
        uint256 indexed proposalID,
        ProposalType proposalType,
        address signer
    );
    event ProposalExecuted(
        ProposalType proposalType,
        uint256 proposalId
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
    
    
    function proposeClaimSchedule(
        uint256 _icoStageID,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _claimInterval,
        uint256 _slicePeriod
    ) external onlyRole(VESTING_AUTHORISER_ROLE) {
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

        bytes memory _paramsData = abi.encode(
            ClaimScheduleParam({
                icoStageID: _icoStageID,
                startTime: _startTime,
                endTime: _endTime,
                claimInterval: _claimInterval,
                slicePeriod: _slicePeriod
            })
        );
        bytes32 _proposalHash = keccak256(_paramsData);
        proposalCount ++;

        Proposal storage proposal = proposals[proposalCount];
        proposal.proposalHash = _proposalHash;
        proposal.proposalType = ProposalType.SetClaimSchedule;
        proposal.paramsData = _paramsData;
        proposal.timestamp = block.timestamp;
        
        emit ProposalCreated(
            proposalCount,
            ProposalType.SetClaimSchedule,
            _proposalHash
        );
    }

    /**
        @dev Function to update the claim schedule
    */
    function proposeUpdateClaimSchedule(
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
        bytes memory _paramsData = abi.encode(
            ClaimScheduleParam({
                icoStageID: _icoStageID,
                startTime: _startTime,
                endTime: _endTime,
                claimInterval: _claimInterval,
                slicePeriod: _slicePeriod
            })
        );
        bytes32 _proposalHash = keccak256(_paramsData);
        proposalCount ++;

        Proposal storage proposal = proposals[proposalCount];
        proposal.proposalHash = _proposalHash;
        proposal.proposalType = ProposalType.SetClaimSchedule;
        proposal.paramsData = _paramsData;
        proposal.timestamp = block.timestamp;

        emit ProposalCreated(
            proposalCount,
            ProposalType.UpdateClaimSchedule,
            _proposalHash
        );
    }

    function proposeUpdateInterface(address _newInterface) external onlyRole(OWNER_ROLE) {
        bytes memory data = abi.encode(_newInterface);
        bytes32 proposalHash = keccak256(data);
        proposalCount++;
        
        Proposal storage proposal = proposals[proposalCount];
        proposal.proposalType = ProposalType.UpdateInterface;
        proposal.proposalHash = proposalHash;
        proposal.timestamp = block.timestamp;
        proposal.paramsData = data;
        
        emit ProposalCreated(proposalCount, ProposalType.UpdateInterface, proposalHash);
    }

    function proposeUpgrade(address _newImplementation) external onlyRole(UPGRADER_ROLE) {
        bytes memory data = abi.encode(_newImplementation);
        bytes32 proposalHash = keccak256(data);
        proposalCount++;
        
        Proposal storage proposal = proposals[proposalCount];
        proposal.proposalType = ProposalType.UpgradeContract;
        proposal.proposalHash = proposalHash;
        proposal.timestamp = block.timestamp;
        proposal.paramsData = data;
        
        emit ProposalCreated(proposalCount, ProposalType.UpgradeContract, proposalHash);
    }

    function proposeUpdateRequiredConfirmations(
        uint256 _requiredConfirmations
    ) external onlyRole(OWNER_ROLE) {
        require(
            _requiredConfirmations > 0,
            "ICO: Should be greater than 0"
        );
        bytes memory data = abi.encode(_requiredConfirmations);
        bytes32 proposalHash = keccak256(data);
        proposalCount++;

        Proposal storage proposal = proposals[proposalCount];
        proposal.paramsData = data;
        proposal.proposalType = ProposalType.UpdateRequiredConfirmations;
        proposal.proposalHash = proposalHash;
        proposal.timestamp = block.timestamp;
        emit ProposalCreated(proposalCount, ProposalType.UpgradeContract, proposalHash);
    }

    function approveProposal(uint256 _proposalId) external onlyRole(SIGNER_ROLE) {
        Proposal storage proposal = proposals[_proposalId];
        require(
            _proposalId <= proposalCount,
            "ex1Vesting: Invalid Proposal ID"
        );
        require(
            !proposal.executed,
            "ex1Vesting: Proposal already Executed!"
        );
        require(
            !proposal.hasApproved[_msgSender()],
            "ex1Vesting: Already approved by the signer!"
        );
        proposal.hasApproved[_msgSender()] = true;
        proposal.approvalCounts ++;

        emit ProposalApproved(_proposalId, proposal.proposalType, _msgSender());

        if(proposal.approvalCounts >= requiredConfirmations) {
            executeProposal(_proposalId);
        }
    }

    function executeProposal(
        uint256 _proposalId
    ) internal returns(bool) {
        Proposal storage proposal = proposals[_proposalId];
        
        require(
            !proposal.executed,
            "ex1Vesting: Proposal already approved!"
        );
        require(
            proposal.approvalCounts >= requiredConfirmations,
            "ex1Vesting: Insufficient Signer approvals"
        );
        if( proposal.proposalType == ProposalType.SetClaimSchedule ) {
            ClaimScheduleParam memory params = abi.decode(proposal.paramsData, (ClaimScheduleParam));
            _setClaimSchedule(params);
        }
        else if( proposal.proposalType == ProposalType.UpdateClaimSchedule ) {
            ClaimScheduleParam memory params = abi.decode(proposal.paramsData, (ClaimScheduleParam));
            _updateClaimSchedule(params);
        }  
        else if (proposal.proposalType == ProposalType.UpdateInterface) {
            address newInterface = abi.decode(proposal.paramsData, (address));
            _updateInterface(newInterface);
        } else if (proposal.proposalType == ProposalType.UpgradeContract) {
            address newImplementation = abi.decode(proposal.paramsData, (address));
            _authorizeUpgrade(newImplementation);
        } else if(proposal.proposalType == ProposalType.UpdateRequiredConfirmations){
            uint256 _requiredConfirmations = abi.decode(proposal.paramsData, (uint256));
            _updateRequiredConfirmation(_requiredConfirmations);
        }                
        else {
            uint256 invalid = 0;
            require(
                invalid == 1,
                "ICOVesting: Not Proposal Type found!"
            );
            return false;
        }   
        emit ProposalExecuted(
            proposal.proposalType,
            _proposalId
        );  
        proposal.executed = true;          
        return true;
    }
   
    function _setClaimSchedule(ClaimScheduleParam memory _params) internal {
        claimSchedules[_params.icoStageID] = claimSchedule({
            icoStageID: _params.icoStageID,
            startTime: _params.startTime,
            endTime: _params.endTime,
            interval: _params.claimInterval,
            slicePeriod: _params.slicePeriod
        });
        emit ClaimScheduleCreated(
            _params.icoStageID,
            _params.startTime,
            _params.endTime,
            _params.claimInterval,
            _params.slicePeriod,
            block.timestamp
        );
    }

    /**
        @dev Function to update the claim schedule
    */
    function _updateClaimSchedule(ClaimScheduleParam memory _params) internal {        
        uint256 _icoStageID = _params.icoStageID;
        claimSchedules[_icoStageID].startTime = _params.startTime;
        claimSchedules[_icoStageID].endTime = _params.endTime;
        claimSchedules[_icoStageID].interval = _params.claimInterval;
        claimSchedules[_icoStageID].slicePeriod = _params.slicePeriod;
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

    function _updateInterface(address _newInterface) internal {
        icoInterface = Iex1ICO(_newInterface);
    }

    function _updateRequiredConfirmation(uint256 _requiredConfirmations) internal {
        requiredConfirmations = _requiredConfirmations;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}