// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ICOVesting} from "../../src/ex1ICOVesting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Ex1ICOVesting is Script {
    ICOVesting public instance;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        instance = new ICOVesting();

        vm.stopBroadcast();
    }
}

/*
    Deployment script: 
    forge script script/DeployVesting/icoVesting.s.sol --rpc-url=$BSC_TESTNET_RPC_URL --private-key=$BSC_TESTNET_PRIVATE_KEY --broadcast --etherscan-api-key=$BSC_TESTNET_API_KEY --verify  
*/