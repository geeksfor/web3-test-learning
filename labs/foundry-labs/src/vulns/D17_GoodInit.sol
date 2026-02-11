// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ✅ 使用 OpenZeppelin 的 Initializable：提供 initializer / reinitializer / _disableInitializers
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * D17 - GoodInit（修复版：initializer 防重复初始化）
 *
 * 修复点：
 * 1) initialize() 使用 initializer：只能成功一次，后续调用会 revert
 * 2) constructor 调用 _disableInitializers()：防止“实现合约地址(Impl)自身”被人初始化
 *
 * 说明：
 * - 这里用最小依赖：只引入 Initializable，不依赖 OwnableUpgradeable，避免你 OZ 版本差异导致编译失败。
 * - owner/treasury 自己维护，足够演示“初始化漏洞”与“修复”。
 */
contract D17_GoodInit is Initializable {
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

    /// @dev ✅ 最佳实践：锁死实现合约自身的初始化（防 Impl 被 initialize）
    constructor() {
        // 先不实现这个函数，否则无法直接调用该合约的initialize函数，需要引入proxy概念
        // _disableInitializers();
    }

    /// @notice ✅ 修复：initializer 保证只能初始化一次
    function initialize(
        address _owner,
        address _treasury
    ) external initializer {
        require(_owner != address(0), "zero owner");
        require(_treasury != address(0), "zero treasury");

        owner = _owner;
        treasury = _treasury;

        emit Initialized(_owner, _treasury);
    }

    /// @notice 典型敏感操作：只有 owner 能改 treasury
    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "zero treasury");
        emit TreasuryChanged(treasury, newTreasury);
        treasury = newTreasury;
    }

    /// @notice 演示危害/功能：owner 可把合约里的 ETH sweep 到 treasury
    function sweepETH() external onlyOwner {
        uint256 bal = address(this).balance;
        (bool ok, ) = treasury.call{value: bal}("");
        require(ok, "transfer failed");
        emit Swept(treasury, bal);
    }

    receive() external payable {}

    // ===========================
    // （可选加分）V2 初始化示例：升级后新增字段用 reinitializer(2)
    // ===========================
    uint256 public feeBps;

    function initializeV2(uint256 _feeBps) external reinitializer(2) {
        require(_feeBps <= 10_000, "fee too high");
        feeBps = _feeBps;
    }
}
