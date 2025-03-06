// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/ex1Token.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Script.sol";

contract DeployUUPSProxy is Script {
    function run() public {
        // Replace with your deployed implementation address
        address _implementation = 0x7501A998E9Ff667B6Db63706B8a08c3eda53eFAE;
        
        
        // Define initial owners and required approvals
        address[] memory initialApprovers = new address[](3);
        initialApprovers[0] = 0x2073114Ccee10DEc5FE5a93438cc5204a3eCaCB2; // Replace with actual owner addresses
        initialApprovers[1] = 0xd7BfFa422717c0175622296208bBcA8D61B8c3bd;
        initialApprovers[2] = 0x0f22F0f1C70b0277dEE7F0FF1ac480CB594Ca450;
        uint256 requiredApprovals = 2; // Number of required approvals for multisig

        vm.startBroadcast();

        // Encode the initializer function call
        bytes memory data = abi.encodeWithSelector(
            EX1.initialize.selector,
            initialApprovers,
            requiredApprovals
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(_implementation, data);

        vm.stopBroadcast();
        
        console.log("UUPS Proxy Address:", address(proxy));
    }
}

// forge script script/DeployToken/deployProxy.s.sol:DeployUUPSProxy --rpc-url=$BSC_TESTNET_RPC_URL --private-key=$BSC_TESTNET_PRIVATE_KEY --broadcast --etherscan-api-key=$BSC_TESTNET_API_KEY --verify