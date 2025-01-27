// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/Ethereum/ex1EthICO.sol";
import "forge-std/Script.sol";

contract DeployTokenImplementation is Script {
    function run() public {
        // Use address provided in config to broadcast transactions
        vm.startBroadcast();
        // Deploy the ERC-20 token
        Ex1ICO implementation = new Ex1ICO();
        // Stop broadcasting calls from our address
        vm.stopBroadcast();
        // Log the token address
        console.log("Token Implementation Address:", address(implementation));
    }
}

/*
forge script script/DeployICOEth/ex1ICOv2.s.sol --rpc-url=$ETH_HOLESKY_RPC_URL --private-key=$ETH_HOLESKY_PRIVATE_KEY --broadcast --etherscan-api-key=$ETH_HOLESKY_API_KEY --verify  
*/