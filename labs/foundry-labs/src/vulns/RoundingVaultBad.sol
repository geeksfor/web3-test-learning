// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @notice 教学用：故意做“存款向下取整 / 赎回向上取整”的不一致舍入
/// 结果：存在循环套利空间（尤其在多次小额操作时累计出差）

contract RoundingVaultBad is ERC20 {
    using Math for uint256;

    IERC20 public immutable asset; // underlying

    constructor(IERC20 _asset) ERC20("BadShare", "BSH") {
        asset = _asset;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice 存款：shares = floor(assets * totalSupply / totalAssets)
    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares) {
        require(assets > 0, "zero");
        uint256 ts = totalSupply();
        uint256 ta = totalAssets();

        if (ts == 0 || ta == 0) {
            shares = assets; // 1:1 初始化
        } else {
            shares = (assets * ts) / ta; // floor
        }

        require(shares > 0, "zero shares"); // 防止用户被白嫖（但也会制造“卡边界”行为）
        _mint(receiver, shares);

        require(asset.transferFrom(msg.sender, address(this), assets), "tf");
    }

    /// @notice 赎回：assets = ceil(shares * totalAssets / totalSupply)
    /// 这就是坏点：与 deposit 的 floor 方向不一致
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets) {
        require(shares > 0, "zero");
        if (msg.sender != owner) {
            uint256 a = allowance(owner, msg.sender);
            require(a >= shares, "no allowance");
            _approve(owner, msg.sender, a - shares);
        }

        uint256 ts = totalSupply();
        uint256 ta = totalAssets();
        // ceilDiv = (x + y - 1) / y
        // 这个公式完成了向上取整
        assets = (shares * ta + ts - 1) / ts; // ceil
        _burn(owner, shares);

        require(asset.transfer(receiver, assets), "t");
    }

    /// @notice 攻击常用：往 vault “捐赠”资产改变比例（真实世界可能来自 direct transfer）
    function donate(uint256 assets) external {
        require(asset.transferFrom(msg.sender, address(this), assets), "tf");
    }
}
