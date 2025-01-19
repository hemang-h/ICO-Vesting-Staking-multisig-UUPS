// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Ex1ICO} from "../src/ex1ICO.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ex1ICOScript is Script {
    Ex1ICO public ex1Token;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ex1Token = new Ex1ICO(0x6B1fdD1E4b2aE9dE8c5764481A8B6d00070a3096);

        vm.stopBroadcast();
    }
}
