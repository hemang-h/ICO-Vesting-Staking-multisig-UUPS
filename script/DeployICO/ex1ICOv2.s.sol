// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ex1ICO} from "../../src/ex1ICOv2.sol";
import "forge-std/Script.sol";

contract DeployTokenImplementation is Script {
    Ex1ICO public instance;
    function setUp() public {}

    function run() public {
        // Use address provided in config to broadcast transactions
        vm.startBroadcast();
        // Deploy the ERC-20 token
        instance = new Ex1ICO();
        // Stop broadcasting calls from our address
        vm.stopBroadcast();
    }
}

/*
forge script script/DeployICO/ex1ICOv2.s.sol --rpc-url=$BSC_TESTNET_RPC_URL --private-key=$BSC_TESTNET_PRIVATE_KEY --broadcast --etherscan-api-key=$BSC_TESTNET_API_KEY --verify  
*/