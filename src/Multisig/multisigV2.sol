// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract MultisigGovernance is AccessControlUpgradeable {
    enum ProposalStatus { Pending, Approved, Executed, Rejected }
    enum ProposalType {Withdraw}

    struct Proposal {
        bytes32 proposalHash;
        uint256 proposalType;
        bytes proposalData;
        uint256 approvalCount;
        ProposalStatus status;
        mapping(address => bool) approvals;
        uint256 createdAt;
    }

    uint256 public requiredConfirmations;
    mapping(uint256 => Proposal) internal proposals;
    uint256 internal proposalNonce;

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");

    event ProposalCreated(uint256 indexed proposalId, bytes32 proposalHash, uint256 proposalType);
    event ProposalApproved(uint256 indexed proposalId, address approver);
    event ProposalExecuted(uint256 indexed proposalId);

    function __MultisigGovernance_init(uint256 _requiredConfirmations) internal initializer {
        requiredConfirmations = _requiredConfirmations;
    }

    function createProposal(
        uint256 _proposalType, 
        bytes memory _proposalData
    ) internal returns (uint256 proposalId) {
        require(hasRole(PROPOSER_ROLE, msg.sender), "Unauthorized proposer");
        
        proposalId = proposalNonce++;
        Proposal storage proposal = proposals[proposalId];
        
        proposal.proposalHash = keccak256(_proposalData);
        proposal.proposalType = _proposalType;
        proposal.proposalData = _proposalData;
        proposal.status = ProposalStatus.Pending;
        proposal.createdAt = block.timestamp;

        emit ProposalCreated(proposalId, proposal.proposalHash, _proposalType);
        return proposalId;
    }

    function approveProposal(uint256 _proposalId) public {
        require(hasRole(APPROVER_ROLE, msg.sender), "Unauthorized approver");
        
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status == ProposalStatus.Pending, "Invalid proposal status");
        require(!proposal.approvals[msg.sender], "Already approved");

        proposal.approvals[msg.sender] = true;
        proposal.approvalCount++;

        emit ProposalApproved(_proposalId, msg.sender);

        if (proposal.approvalCount >= requiredConfirmations) {
            proposal.status = ProposalStatus.Approved;
        }
    }

    function _checkProposalApproved(uint256 _proposalId) internal view returns (bool) {
        return proposals[_proposalId].status == ProposalStatus.Approved;
    }

    function _getProposalData(uint256 _proposalId) internal view returns (bytes memory) {
        return proposals[_proposalId].proposalData;
    }
}