// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SimpleERC20ApproveRace.sol";

contract AllowanceSpender {
    SimpleERC20ApproveRace public immutable token;

    constructor(SimpleERC20ApproveRace _token) {
        token = _token;
    }

    // spender 利用 allowance 从 victim 拉钱
    function spendFrom(address victim, address to, uint256 amount) external {
        token.transferFrom(victim, to, amount);
    }
}
