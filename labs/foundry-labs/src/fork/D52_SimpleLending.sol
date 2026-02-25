// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/console2.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function balanceOf(address who) external view returns (uint256);
}

/// @notice 最小可控价格 Oracle（测试用）
contract D52_OracleMock {
    // price in WAD, e.g. 2000e18 means $2000 per collateral token
    uint256 public priceWad;

    function setPrice(uint256 newPriceWad) external {
        priceWad = newPriceWad;
    }
}

/// @notice 最小 ERC20（测试用）：mint 给任何人
contract D52_TestERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract D52_SimpleLending {
    uint256 internal constant WAD = 1e18;

    error NotHealthy(uint256 debtValue, uint256 maxDebtValue); /// 借钱后会导致仓位不健康（超 LTV）就报错
    error NotLiquidatable(); /// 没到清算条件，禁止清算
    error RepayTooMuch(uint256 maxRepay); /// 清算 repay 超过 closeFactor 上限
    error Zero();

    IERC20 public immutable collateralToken; /// 抵押品 token（比如 ETH 的包装币 WETH，或你这里的 COL）
    IERC20 public immutable debtToken; // 借出去的“债务币”，这里简化当作 1 美元（$1）稳定币。
    D52_OracleMock public immutable oracle; /// 价格预言机，给出“1 个抵押币值多少美元”（用 WAD 表示）

    // 参数（WAD 比例）
    uint256 public immutable ltvWad; /// 最大借款比例（最多借到抵押价值的 75%） e.g. 0.75e18
    uint256 public immutable ltWad; /// 清算阈值（债务超过抵押价值的 80% 就可清算） e.g. 0.80e18
    uint256 public immutable closeFactorWad; /// 一次清算最多还多少债（例如 50%） e.g. 0.50e18
    uint256 public immutable bonusWad; /// 清算奖励 e.g. 0.05e18

    mapping(address => uint256) public collateralOf; /// 用户存了多少抵押币（数量，不是价值） amount
    mapping(address => uint256) public debtOf; /// 用户欠了多少债务币（数量，简化为美元稳定币数量）

    constructor(
        IERC20 _collateralToken,
        IERC20 _debtToken,
        D52_OracleMock _oracle,
        uint256 _ltvWad,
        uint256 _ltWad,
        uint256 _closeFactorWad,
        uint256 _bonusWad
    ) {
        collateralToken = _collateralToken;
        debtToken = _debtToken;
        oracle = _oracle;
        ltvWad = _ltvWad;
        ltWad = _ltWad;
        closeFactorWad = _closeFactorWad;
        bonusWad = _bonusWad;
    }

    function deposit(uint256 amount) external {
        if (amount == 0) revert Zero();
        collateralToken.transferFrom(msg.sender, address(this), amount);
        collateralOf[msg.sender] += amount;
    }

    function borrow(uint256 amount) external {
        if (amount == 0) revert Zero();

        // 先把债务加上，检查是否健康；不健康则回滚
        uint256 newDebt = debtOf[msg.sender] + amount;

        uint256 maxDebtValue = (collateralValueWad(msg.sender) * ltvWad) / WAD; // $ value in WAD
        uint256 newDebtValue = newDebt; // debt token assumed $1 => value = amount * 1e18

        if (newDebtValue > maxDebtValue) {
            revert NotHealthy(newDebtValue, maxDebtValue);
        }

        debtOf[msg.sender] = newDebt;
        // 简化：借到的“美元”债务 token 直接转给用户（测试里预先铸给池子）
        debtToken.transfer(msg.sender, amount);
    }

    function isLiquidatable(address user) public view returns (bool) {
        // 可清算条件：debtValue > collateralValue * LT
        uint256 debtValue = debtOf[user];
        uint256 threshold = (collateralValueWad(user) * ltWad) / WAD;
        return debtValue > threshold;
    }

    function liquidate(address user, uint256 repayAmount) external {
        if (!isLiquidatable(user)) revert NotLiquidatable();
        if (repayAmount == 0) revert Zero();

        uint256 userDebt = debtOf[user];
        console2.log("userDebt", userDebt);
        uint256 maxRepay = (userDebt * closeFactorWad) / WAD;
        console2.log("maxRepay", maxRepay);
        if (repayAmount > maxRepay) revert RepayTooMuch(maxRepay);

        // 清算人把债务 token 付给池子（相当于替 user 还债）
        debtToken.transferFrom(msg.sender, address(this), repayAmount);
        debtOf[user] = userDebt - repayAmount;

        // 计算应拿走多少抵押品：repayValue = repayAmount * $1
        // seizeValue = repayValue * (1 + bonus)
        // seizeAmount = seizeValue / price
        uint256 price = oracle.priceWad();
        uint256 seizeValueWad = ((repayAmount) * (WAD + bonusWad)) / WAD;
        console2.log("seizeValueWad", seizeValueWad);
        uint256 seizeAmount = (seizeValueWad * WAD) / price;

        // 防止拿超（真实协议可能允许把剩余全拿走并清空仓位；这里做简单保护）
        uint256 userCol = collateralOf[user];
        if (seizeAmount > userCol) seizeAmount = userCol;

        collateralOf[user] = userCol - seizeAmount;
        collateralToken.transfer(msg.sender, seizeAmount);
    }

    function collateralValueWad(address user) public view returns (uint256) {
        // amount * price / 1e18 => $ value WAD
        return (collateralOf[user] * oracle.priceWad()) / WAD;
    }
}
