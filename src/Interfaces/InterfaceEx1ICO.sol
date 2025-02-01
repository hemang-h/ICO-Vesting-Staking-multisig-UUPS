// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

interface Iex1ICO {
    function totalTokensSold() external view returns(uint256);
    function totalBuyers() external view returns (uint256);
    function latestICOStageID() external view returns (uint256);
    function stageIDs(uint256) external view returns(uint256);

    function HoldersCumulativeBalance(address) external view returns (uint256);
    function tokenRaisedPerStage(address) external returns(bool);

    function UserDepositsPerICOStage(uint256, address) external view returns (uint256);
    function HoldersExists(uint256, address) external view returns(bool);

    function icoStages(uint256) external view returns(uint256, uint256, uint256, uint256, bool);

    function createICOStage(bytes memory) external;
}