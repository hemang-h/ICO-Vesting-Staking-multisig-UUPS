const { ethers } = require('ethers');

// Your addresses
const NEW_IMPLEMENTATION = "0xb2A034dbc8346bB4716820559378a502B5b5a81C";
const EX1_TOKEN = "0x6B1fdD1E4b2aE9dE8c5764481A8B6d00070a3096";

// Helper function to encode the initialize function call
function encodeInitializeCall(ex1TokenAddress) {
    // Create interface with just the initialize function
    const abiInterface = new ethers.Interface([
        "function initialize(address _ex1Token)"
    ]);
    
    // Encode the initialize function call
    const encodedCall = abiInterface.encodeFunctionData(
        "initialize",
        [ex1TokenAddress]
    );
    
    return encodedCall;
}

async function main() {
    try {
        // 1. payableAmount - should be 0 as we don't need to send ETH
        const payableAmount = "0";
        
        // 2. newImplementation - the address of your new implementation
        const newImplementation = NEW_IMPLEMENTATION;
        
        // 3. data - encoded initialize call
        const data = encodeInitializeCall(EX1_TOKEN);
        
        console.log("\n=== Upgrade Parameters ===");
        console.log("payableAmount:", payableAmount);
        console.log("newImplementation:", newImplementation);
        console.log("data:", data);
        
        return {
            payableAmount,
            newImplementation,
            data
        };
    } catch (error) {
        console.error("Error generating upgrade parameters:", error);
    }
}

// Run the script
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });