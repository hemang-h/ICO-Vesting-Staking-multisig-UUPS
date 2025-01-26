// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDCMockToken is ERC20 {
    constructor() ERC20("USDCMock", "USDC") {
        _mint(msg.sender, 10000000000000 * 10 ** 18);
    }
    function mintMore(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}