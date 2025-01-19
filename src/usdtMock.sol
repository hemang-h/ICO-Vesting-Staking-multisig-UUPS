// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDTMockToken is ERC20 {
    constructor() ERC20("USDTMock", "USDT") {
        _mint(msg.sender, 10000000000000 * 10 ** 18);
    }
    function mintMore(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}