// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract OwnableBadMint is Ownable {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(address initialOwner) Ownable(initialOwner) {}

    // ❌ 错误：没有 onlyOwner，任何人都能 mint 给任何人
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
