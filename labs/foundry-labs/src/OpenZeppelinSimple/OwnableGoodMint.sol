// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract OwnableGoodMint is Ownable {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function mint(address to, uint256 amount) external onlyOwner {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
