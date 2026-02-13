// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleERC20ApproveRace {
    string public name = "RaceToken";
    string public symbol = "RACE";
    uint8 public decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    error InsufficientBalance(address from, uint256 have, uint256 need);
    error InsufficientAllowance(
        address owner,
        address spender,
        uint256 have,
        uint256 need
    );

    // 铸币
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        // 典型漏洞点：覆盖式写入 value
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        uint256 bal = balanceOf[msg.sender];
        if (bal < value) revert InsufficientBalance(msg.sender, bal, value);
        balanceOf[msg.sender] = bal - value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        uint256 bal = balanceOf[from];
        if (bal < value) revert InsufficientBalance(from, bal, value);

        uint256 a = allowance[from][msg.sender];
        if (a < value) revert InsufficientAllowance(from, msg.sender, a, value);

        allowance[from][msg.sender] = a - value;
        balanceOf[from] = bal - value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }

    // 安全改法 B：差量增加（更推荐）
    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) external returns (bool) {
        uint256 cur = allowance[msg.sender][spender];
        uint256 next = cur + addedValue;
        allowance[msg.sender][spender] = next;
        emit Approval(msg.sender, spender, next);
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) external returns (bool) {
        uint256 cur = allowance[msg.sender][spender];
        require(cur >= subtractedValue, "decrease below zero");
        uint256 next = cur - subtractedValue;
        allowance[msg.sender][spender] = next;
        emit Approval(msg.sender, spender, next);
        return true;
    }
}
