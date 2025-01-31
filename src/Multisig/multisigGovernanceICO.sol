// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../Interfaces/InterfaceEx1ICO.sol";

contract MultiSigGovernanceICO is AccessControlUpgradeable{
    
    Iex1ICO public icoInterface = Iex1ICO(0x301Cc53ff52Bf79C15249fa25d1e8aE8e222F205);

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant APPROVER_ROLE =keccak256("APPROVER_ROLE"); 
    
    uint256 public requiredConfirmations;
    uint256 public proposalCount;

    enum ProposalType {
        CreateICOStage,
        UpdateICOStage,
        Withdraw,
        UpgradeContract,
        UpdgradeInterface,
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
    struct ICOStageParams {
        uint256 startTime;
        uint256 endTime;
        uint256 stageID;
        uint256 tokenPrice;
        bool isActive;
    }
    mapping(uint256 => Proposal) public proposals;

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

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(PROPOSER_ROLE, _msgSender());
        _grantRole(APPROVER_ROLE, _msgSender());
    }

    function proposeCreateICOStage ( 
        bytes memory data,
        address _caller 
    ) public onlyRole(PROPOSER_ROLE) returns(bool) {
        require(
            hasRole(PROPOSER_ROLE, _caller),
            "ExICO: Caller doesn't have PROPOSER_ROLE!"
        );        
        bytes32 _proposalHash = keccak256(data);
        uint256 _proposalId = proposalCount ++;

        Proposal storage proposal = proposals[_proposalId];
        proposal.proposalID = _proposalId;
        proposal.proposalHash = _proposalHash;
        proposal.paramsData = data;
        proposal.proposalType = ProposalType.CreateICOStage;
        proposal.timestamp = block.timestamp;

        emit ProposalCreated(
            proposalCount,
            ProposalType.CreateICOStage,
            _proposalHash
        );

        return true;
    }

    function approveProposal(uint256 _proposalId) external onlyRole(APPROVER_ROLE) {
        Proposal storage proposal = proposals[_proposalId];
        require(
            proposal.executed,
            "ex1ICO: Proposal already approved!"
        );
        require(
            proposal.hasApproved[_msgSender()],
            "ex1ICO: Already approved by the signer!"
        );
        !proposal.hasApproved[_msgSender()];
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
            proposal.executed,
            "ex1ICO: Proposal Already Executed"
        );
        require(
            proposal.approvalCounts >= requiredConfirmations,
            "ex1ICO: Insufficient Approvals"
        );
        if(proposal.proposalType == ProposalType.CreateICOStage) {
            icoInterface.createICOStage(proposal.paramsData);
        }
        return true;
    }
}