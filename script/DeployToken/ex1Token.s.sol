// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/ex1Token.sol";
import "forge-std/Script.sol";

contract DeployTokenImplementation is Script {
    function run() public {
        // Use address provided in config to broadcast transactions
        vm.startBroadcast();
        
        // Deploy the ERC-20 token implementation
        EX1 implementation = new EX1();
        
        // Stop broadcasting calls from our address
        vm.stopBroadcast();
        
        // Log the implementation address
        console.log("Token Implementation Address:", address(implementation));
    }
}

// forge script script/DeployToken/ex1Token.s.sol --rpc-url=$BSC_TESTNET_RPC_URL --private-key=$BSC_TESTNET_PRIVATE_KEY --broadcast --etherscan-api-key=$BSC_TESTNET_API_KEY --verify 
