// 目标：withdraw 里先转账再更新余额，触发典型重入。

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice 最小银行：故意包含重入漏洞
contract MiniBankVuln {
    mapping(address => uint256) public balanceOf;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function deposit() external payable {
        require(msg.value > 0, "zero");
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /// @dev 漏洞点：先 interaction（call）再 effects（更新余额）
    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "insufficient");

        // 1) interaction - 把钱打出去（会触发对方 fallback/receive）
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");

        // 2) effects - 余额最后才扣（太晚了）
        // balanceOf[msg.sender] -= amount;
        balanceOf[msg.sender] = 0;

        emit Withdraw(msg.sender, amount);
    }
}

/// @notice 修复版 1：CEI（Checks-Effects-Interactions）
contract MiniBankCEI {
    mapping(address => uint256) public balanceOf;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function deposit() external payable {
        require(msg.value > 0, "zero");
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "insufficient");

        // effects 先发生
        balanceOf[msg.sender] -= amount;

        // interactions 最后发生
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");

        emit Withdraw(msg.sender, amount);
    }
}

/// @notice 最小版 ReentrancyGuard（教学用）
abstract contract SimpleReentrancyGuard {
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "REENTRANT");
        _locked = 2;
        _;
        _locked = 1;
    }
}

contract MiniBankGuarded is SimpleReentrancyGuard {
    mapping(address => uint256) public balanceOf;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function deposit() external payable {
        require(msg.value > 0, "zero");
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /// @dev 即便你不改顺序，加锁也能挡住“同一交易内再次进入”
    function withdraw(uint256 amount) external nonReentrant {
        require(balanceOf[msg.sender] >= amount, "insufficient");

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");

        balanceOf[msg.sender] -= amount;
        // balanceOf[msg.sender] = 0;

        emit Withdraw(msg.sender, amount);
    }
}
