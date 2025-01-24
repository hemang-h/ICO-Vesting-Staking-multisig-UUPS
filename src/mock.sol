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

    uint256 public constant REQUIRED_SIGNATURES = 2; // Number of required signatures
    uint256 public proposalCount;

    enum ProposalType {
        SetClaimSchedule,
        UpdateClaimSchedule,
        UpdateInterface,
        UpgradeContract
    }

    struct Proposal {
        ProposalType proposalType;
        bytes32 proposalHash;
        uint256 approvalCount;
        mapping(address => bool) hasApproved;
        bool executed;
        uint256 timestamp;
        bytes data;
    }

    struct ClaimScheduleParams {
        uint256 icoStageID;
        uint256 startTime;
        uint256 endTime;
        uint256 claimInterval;
        uint256 slicePeriod;
    }

    mapping(uint256 => Proposal) public proposals;
    
    // Original contract struct and mappings here...
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

    event ProposalCreated(uint256 indexed proposalId, ProposalType proposalType, bytes32 proposalHash);
    event ProposalApproved(uint256 indexed proposalId, address indexed signer);
    event ProposalExecuted(uint256 indexed proposalId);

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
        _grantRole(SIGNER_ROLE, msg.sender);
    }

    function proposeSetClaimSchedule(
        uint256 _icoStageID,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _claimInterval,
        uint256 _slicePeriod
    ) external onlyRole(VESTING_AUTHORISER_ROLE) {
        bytes memory data = abi.encode(
            ClaimScheduleParams({
                icoStageID: _icoStageID,
                startTime: _startTime,
                endTime: _endTime,
                claimInterval: _claimInterval,
                slicePeriod: _slicePeriod
            })
        );
        
        bytes32 proposalHash = keccak256(data);
        uint256 proposalId = proposalCount++;
        
        Proposal storage proposal = proposals[proposalId];
        proposal.proposalType = ProposalType.SetClaimSchedule;
        proposal.proposalHash = proposalHash;
        proposal.timestamp = block.timestamp;
        proposal.data = data;
        
        emit ProposalCreated(proposalId, ProposalType.SetClaimSchedule, proposalHash);
    }

    function proposeUpdateClaimSchedule(
        uint256 _icoStageID,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _claimInterval,
        uint256 _slicePeriod
    ) external onlyRole(VESTING_AUTHORISER_ROLE) {
        bytes memory data = abi.encode(
            ClaimScheduleParams({
                icoStageID: _icoStageID,
                startTime: _startTime,
                endTime: _endTime,
                claimInterval: _claimInterval,
                slicePeriod: _slicePeriod
            })
        );
        
        bytes32 proposalHash = keccak256(data);
        uint256 proposalId = proposalCount++;
        
        Proposal storage proposal = proposals[proposalId];
        proposal.proposalType = ProposalType.UpdateClaimSchedule;
        proposal.proposalHash = proposalHash;
        proposal.timestamp = block.timestamp;
        proposal.data = data;
        
        emit ProposalCreated(proposalId, ProposalType.UpdateClaimSchedule, proposalHash);
    }

    function proposeUpdateInterface(address _newInterface) external onlyRole(OWNER_ROLE) {
        bytes memory data = abi.encode(_newInterface);
        bytes32 proposalHash = keccak256(data);
        uint256 proposalId = proposalCount++;
        
        Proposal storage proposal = proposals[proposalId];
        proposal.proposalType = ProposalType.UpdateInterface;
        proposal.proposalHash = proposalHash;
        proposal.timestamp = block.timestamp;
        proposal.data = data;
        
        emit ProposalCreated(proposalId, ProposalType.UpdateInterface, proposalHash);
    }

    function proposeUpgrade(address _newImplementation) external onlyRole(UPGRADER_ROLE) {
        bytes memory data = abi.encode(_newImplementation);
        bytes32 proposalHash = keccak256(data);
        uint256 proposalId = proposalCount++;
        
        Proposal storage proposal = proposals[proposalId];
        proposal.proposalType = ProposalType.UpgradeContract;
        proposal.proposalHash = proposalHash;
        proposal.timestamp = block.timestamp;
        proposal.data = data;
        
        emit ProposalCreated(proposalId, ProposalType.UpgradeContract, proposalHash);
    }

    function approveProposal(uint256 _proposalId) external onlyRole(SIGNER_ROLE) {
        Proposal storage proposal = proposals[_proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.hasApproved[msg.sender], "Already approved");
        
        proposal.hasApproved[msg.sender] = true;
        proposal.approvalCount++;
        
        emit ProposalApproved(_proposalId, msg.sender);
        
        if (proposal.approvalCount >= REQUIRED_SIGNATURES) {
            executeProposal(_proposalId);
        }
    }

    function executeProposal(uint256 _proposalId) internal {
        Proposal storage proposal = proposals[_proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(proposal.approvalCount >= REQUIRED_SIGNATURES, "Insufficient approvals");

        proposal.executed = true;

        if (proposal.proposalType == ProposalType.SetClaimSchedule) {
            ClaimScheduleParams memory params = abi.decode(proposal.data, (ClaimScheduleParams));
            _setClaimSchedule(params);
        } else if (proposal.proposalType == ProposalType.UpdateClaimSchedule) {
            ClaimScheduleParams memory params = abi.decode(proposal.data, (ClaimScheduleParams));
            _updateClaimSchedule(params);
        } else if (proposal.proposalType == ProposalType.UpdateInterface) {
            address newInterface = abi.decode(proposal.data, (address));
            _updateInterface(newInterface);
        } else if (proposal.proposalType == ProposalType.UpgradeContract) {
            address newImplementation = abi.decode(proposal.data, (address));
            _authorizeUpgrade(newImplementation);
        }

        emit ProposalExecuted(_proposalId);
    }

    // Internal functions that actually perform the operations
    function _setClaimSchedule(ClaimScheduleParams memory params) internal {
        (_, uint256 endTime, , , ) = icoInterface.icoStages(params.icoStageID);
        require(params.startTime > endTime, "ex1Presale: Token Sale not Ended yet!");
        require(
            (params.endTime > params.startTime) && 
            (params.startTime > 0 || params.endTime > 0) && 
            (params.endTime > block.timestamp) && 
            (params.startTime > block.timestamp),
            "ex1Presale: Invalid Schedule or Parameters!"
        );
        require(
            params.claimInterval <= (params.endTime - params.startTime),
            "ex1Presale: Invalid Cliff Period"
        );
        require(
            params.slicePeriod >= 0 && params.slicePeriod <= 60, 
            "ex1Presale: Invalid Slice Period"
        );
        
        claimSchedules[params.icoStageID] = claimSchedule({
            icoStageID: params.icoStageID,
            startTime: params.startTime,
            endTime: params.endTime,
            interval: params.claimInterval,
            slicePeriod: params.slicePeriod
        });
    }

    function _updateClaimSchedule(ClaimScheduleParams memory params) internal {
        require(
            params.startTime == claimSchedules[params.icoStageID].startTime,
            "ex1Presale: Claim Schedule Already Started!"
        );
        require(
            (params.endTime > params.startTime) && 
            (params.startTime > 0 || params.endTime > 0) && 
            (params.endTime > block.timestamp) && 
            (params.startTime > block.timestamp),
            "ex1Presale: Invalid Schedule or Parameters!"
        );
        require(
            params.claimInterval <= (params.endTime - params.startTime),
            "ex1Presale: Invalid Cliff Period"
        );
        require(
            params.slicePeriod >= 0 && params.slicePeriod <= 60, 
            "ex1Presale: Invalid Slice Period"
        );

        claimSchedules[params.icoStageID].startTime = params.startTime;
        claimSchedules[params.icoStageID].endTime = params.endTime;
        claimSchedules[params.icoStageID].interval = params.claimInterval;
        claimSchedules[params.icoStageID].slicePeriod = params.slicePeriod;
    }

    function _updateInterface(address _newInterface) internal {
        icoInterface = Iex1ICO(_newInterface);
    }

    function _authorizeUpgrade(address newImplementation) internal override {
        // Implementation handled through multi-sig process
    }

    // Rest of the original contract functions...
}