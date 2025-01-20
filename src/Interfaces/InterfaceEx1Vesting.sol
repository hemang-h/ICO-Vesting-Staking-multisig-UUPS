// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.23;

interface IVestingICO {
    function claimSchedules(uint256) external returns(uint256, uint256, uint256, uint256, uint256);
}