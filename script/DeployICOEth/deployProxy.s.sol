// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/Ethereum/ex1EthICO.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Script.sol";

contract DeployUUPSProxy is Script {
    function run() public {

        address _implementation = 0xff75080a5eeB88dE6746a0388CDc658E78b1Fc81; // Replace with your token address
        vm.startBroadcast();

        // Encode the initializer function call
        bytes memory data = abi.encodeWithSelector(
            Ex1ICO(_implementation).initialize.selector,
            msg.sender // Initial owner/admin of the contract
        );

        // Deploy the proxy contract with the implementation address and initializer
        ERC1967Proxy proxy = new ERC1967Proxy(_implementation, data);

        vm.stopBroadcast();
        // Log the proxy address
        console.log("UUPS Proxy Address:", address(proxy));
    }
}

/*
    forge script script/DeployICOEth/deployProxy.s.sol:DeployUUPSProxy --rpc-url=$ETH_HOLESKY_RPC_URL --private-key=$ETH_HOLESKY_PRIVATE_KEY --broadcast --etherscan-api-key=$ETH_HOLESKY_API_KEY --verify  
*/