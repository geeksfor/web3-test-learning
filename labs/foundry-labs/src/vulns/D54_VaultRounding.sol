// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(address, address, uint256) external returns (bool);

    function mint(address, uint256) external;
}

/// @dev 测试用最小 ERC20（仅用于本地测试）
contract SimpleERC20 is IERC20Like {
    string public name = "T";
    string public symbol = "T";
    uint8 public decimals = 18;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(
        address to,
        uint256 amount
    ) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external override {
        balanceOf[to] += amount;
    }
}

/// @dev 极简 share 账本（不实现 ERC20 全套，仅演示 rounding）
abstract contract ShareLedger {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function _mint(address to, uint256 shares) internal {
        totalSupply += shares;
        balanceOf[to] += shares;
    }

    function _burn(address from, uint256 shares) internal {
        balanceOf[from] -= shares;
        totalSupply -= shares;
    }
}

/// @dev 漏洞版：允许 deposit 产生 0 share（会吞用户资产）
contract VaultRoundingVuln is ShareLedger {
    IERC20Like public immutable asset;

    constructor(IERC20Like _asset) {
        asset = _asset;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// shares = assets * totalSupply / totalAssets (floor)
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply;
        uint256 assetsInVault = totalAssets();

        // 第一次存入：1:1
        if (supply == 0 || assetsInVault == 0) return assets;

        return (assets * supply) / assetsInVault; // floor
    }

    /// @dev 漏洞：shares 可能为 0，但仍然 transferFrom 收走资产
    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares) {
        shares = _convertToShares(assets);
        // VULN: 没有 require(shares > 0)
        require(asset.transferFrom(msg.sender, address(this), assets), "TF");
        if (shares > 0) _mint(receiver, shares);
    }
}

/// @dev 修复版：0 share 直接 revert，避免吞用户资产；可扩展为 minShares 参数
contract VaultRoundingFixed is ShareLedger {
    error ZeroShares();

    IERC20Like public immutable asset;

    constructor(IERC20Like _asset) {
        asset = _asset;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply;
        uint256 assetsInVault = totalAssets();
        if (supply == 0 || assetsInVault == 0) return assets;
        return (assets * supply) / assetsInVault; // floor
    }

    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares) {
        shares = _convertToShares(assets);
        if (shares == 0) revert ZeroShares(); // ✅ 核心修复点
        require(asset.transferFrom(msg.sender, address(this), assets), "TF");
        _mint(receiver, shares);
    }
}
