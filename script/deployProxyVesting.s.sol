// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../src/ex1ICOVesting.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Script.sol";

contract DeployUUPSProxy is Script {
    function run() public {
        address _implementation = 0x72846212e314e5F93252987867A0b04EFF49e846;
        
        vm.startBroadcast();

        // Encode the initializer function call with no parameters
        bytes memory data = abi.encodeWithSelector(
            ICOVesting(_implementation).initialize.selector  // Remove the parameter
        );

        ERC1967Proxy proxy = new ERC1967Proxy(_implementation, data);

        vm.stopBroadcast();
        console.log("UUPS Proxy Address:", address(proxy));
    }
}

/*

    forge script script/deployProxyVesting.s.sol:DeployUUPSProxy --rpc-url=$BSC_TESTNET_RPC_URL --private-key=$BSC_TESTNET_PRIVATE_KEY --broadcast --etherscan-api-key=$BSC_TESTNET_API_KEY --verify

*/