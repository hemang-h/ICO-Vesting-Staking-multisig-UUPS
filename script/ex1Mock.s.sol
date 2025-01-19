// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ex1MockToken} from "../src/ex1Mock.sol";

contract Ex1Mock is Script {
    ex1MockToken public ex1Token;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ex1Token = new ex1MockToken();

        vm.stopBroadcast();
    }
}