// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * D17 - BadInit (初始化漏洞示例)
 * 漏洞点：initialize() 没有“一次性”保护（没有 initializer / 没有 initialized 锁）
 * 结果：任何人都可以重复调用 initialize()，覆盖 owner / treasury 等关键状态，完成夺权。
 */

contract D17_BadInit {
    address public owner;
    address public treasury;

    event Initialized(address indexed owner, address indexed treasury);
    event TreasuryChanged(
        address indexed oldTreasury,
        address indexed newTreasury
    );
    event Swept(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /// @notice 漏洞：可被重复调用，任何人都能把 owner/treasury 改成自己想要的
    function initialize(address _owner, address _treasury) external {
        owner = _owner;
        treasury = _treasury;
        emit Initialized(_owner, _treasury);
    }

    /// @notice 典型敏感操作：只有 owner 能改 treasury
    function setTreasury(address newTreasury) external onlyOwner {
        emit TreasuryChanged(treasury, newTreasury);
        treasury = newTreasury;
    }

    /// @notice 演示危害：owner 可把合约里的 ETH 全部转走
    function sweepETH() external onlyOwner {
        uint256 bal = address(this).balance;
        (bool ok, ) = treasury.call{value: bal}("");
        require(ok, "transfer failed");
        emit Swept(treasury, bal);
    }

    /// @notice 方便测试：往合约里打 ETH
    receive() external payable {}
}
