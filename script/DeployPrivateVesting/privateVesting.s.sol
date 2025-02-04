// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {PrivateVesting} from "../../src/ex1PrivateVesting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Ex1PrivateVesting is Script {
    PrivateVesting public instance;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        instance = new PrivateVesting();

        vm.stopBroadcast();
    }
}

/*
    Deployment script: 
    forge script script/DeployPrivateVesting/privateVesting.s.sol --rpc-url=$BSC_TESTNET_RPC_URL --private-key=$BSC_TESTNET_PRIVATE_KEY --broadcast --etherscan-api-key=$BSC_TESTNET_API_KEY --verify  
*/