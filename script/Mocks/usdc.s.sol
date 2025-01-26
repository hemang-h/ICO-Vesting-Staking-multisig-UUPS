// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {USDCMockToken} from "../../src/mocks/usdcMock.sol";

contract USDC is Script {
    USDCMockToken public ex1Token;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ex1Token = new USDCMockToken();

        vm.stopBroadcast();
    }
}