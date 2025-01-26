// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {USDTMockToken} from "../../src/mocks/usdtMock.sol";

contract USDT is Script {
    USDTMockToken public ex1Token;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ex1Token = new USDTMockToken();

        vm.stopBroadcast();
    }
}