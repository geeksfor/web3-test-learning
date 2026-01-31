// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleERC20 {
    string public name = "Simple";
    string public symbol = "SIM";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    // allowance 这张表是“owner 授权 spender 能花多少”。
    mapping(address=>mapping (address=>uint256)) public allowance;

    error InsufficientBalance(address from, uint256 have, uint256 need);
    error InvalidSpender(address spender);
    error ZeroAddress();
    error InsufficientAllowance(address spender, uint256 have, uint256 need);

    event Transfer(address indexed owner, address indexed spender, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    // 授权
    function approve(address spender, uint256 amount) external returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        if(spender == address(0)) revert InvalidSpender(spender);

        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    } 

    // 转账
    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 bal = balanceOf[msg.sender];
        if (bal < amount) revert InsufficientBalance(msg.sender, bal, amount);

        balanceOf[msg.sender] = bal - amount;
        balanceOf[to] += amount;

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        address spender = msg.sender;

        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);

        return true;
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 current = allowance[owner][spender];

        // “无限授权”优化：max 表示不扣减
        if(current != type(uint256).max) {
            if (current < amount) revert InsufficientAllowance(spender, current, amount);

            unchecked {
                uint256 newAllowance = current - amount;
                allowance[owner][spender] = newAllowance;
            }

            // 很多主流实现会在 allowance 变化时 emit Approval（建议做，方便 indexer/前端）
            emit Approval(owner, spender, allowance[owner][spender]);
        }else {
            // 如果不是 max，就已经 emit 过了；max 情况一般不 emit Approval（因为没变化）
            // 你也可以选择 emit，但测试要跟着改。
        }
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();

        uint256 bal = balanceOf[from];
        if (bal < amount) revert InsufficientBalance(from, bal, amount);

        unchecked {
            balanceOf[from] = bal - amount;
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
    }
}
