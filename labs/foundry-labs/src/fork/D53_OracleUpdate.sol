// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice 最小 Oracle：手动喂价 + 记录更新时间
contract MockOracle {
    uint256 public priceE18; // 价格，18位精度（例如：ETH=2000e18）
    uint256 public updatedAt; // 最近一次更新时间戳

    event PriceUpdated(uint256 priceE18, uint256 updatedAt);

    function update(uint256 newPriceE18) external {
        priceE18 = newPriceE18;
        updatedAt = block.timestamp;
        emit PriceUpdated(newPriceE18, updatedAt);
    }

    function getPrice() external view returns (uint256) {
        return priceE18;
    }
}

/// @notice 最小借贷：只做“清算判断”所需逻辑
contract SimpleLending {
    uint256 public constant WAD = 1e18;

    MockOracle public immutable oracle;

    // liquidationThreshold = 80% 表示：抵押价值打8折后仍需 >= 债务，否则可清算
    uint256 public immutable liquidationThresholdE18; // 0.8e18
    uint256 public immutable maxOracleDelay; // 允许的最大“价格陈旧”时间（秒）

    mapping(address => uint256) public collateralEth; // 抵押 ETH 数量（18位）
    mapping(address => uint256) public debtUsd; // 债务（以 USD 计价，18位）

    error StalePrice(uint256 updatedAt, uint256 nowTs);

    constructor(MockOracle _oracle, uint256 _liqThresholdE18, uint256 _maxOracleDelay) {
        oracle = _oracle;
        liquidationThresholdE18 = _liqThresholdE18;
        maxOracleDelay = _maxOracleDelay;
    }

    function depositCollateral(uint256 ethAmountE18) external {
        collateralEth[msg.sender] += ethAmountE18;
    }

    function borrow(uint256 usdAmountE18) external {
        // 这里故意不做风控校验（方便 D53 聚焦“清算判断变化”）
        debtUsd[msg.sender] += usdAmountE18;
    }

    function _priceFresh() internal view {
        uint256 t = oracle.updatedAt();
        if (block.timestamp > t + maxOracleDelay) {
            revert StalePrice(t, block.timestamp);
        }
    }

    /// @notice 抵押价值（USD）= collateralEth * price
    function collateralValueUsd(address user) public view returns (uint256) {
        uint256 p = oracle.priceE18();
        return (collateralEth[user] * p) / WAD;
    }

    /// @notice 是否可清算：collateralValue * threshold < debt
    /// @dev 加了 freshness 校验：过期就直接 revert（审计常见建议）
    function isLiquidatable(address user) external view returns (bool) {
        _priceFresh();

        uint256 value = collateralValueUsd(user);
        uint256 discounted = (value * liquidationThresholdE18) / WAD;
        return discounted < debtUsd[user];
    }
}
