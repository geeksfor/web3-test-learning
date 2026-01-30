// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleERC20 {
    string public name = "Simple";
    string public symbol = "SIM";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;

    error InsufficientBalance(address from, uint256 have, uint256 need);

    event Transfer(address indexed from, address indexed to, uint256 amount);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 bal = balanceOf[msg.sender];
        if (bal < amount) revert InsufficientBalance(msg.sender, bal, amount);

        balanceOf[msg.sender] = bal - amount;
        balanceOf[to] += amount;

        emit Transfer(msg.sender, to, amount);
        return true;
    }
}
