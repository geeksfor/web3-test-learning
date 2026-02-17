// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./D23_MockERC20.sol";

// 这段定义了 借款人（borrower）必须实现的回调函数：

// lender 把钱转给 borrower 之后，会立刻调用 borrower 的 onFlashLoan(...)

// 你可以在回调里做任何操作（操纵价格、套利、清算、换币……）

// 关键要求：回调结束前，borrower 必须把 amount + fee 还给 lender（通过 ERC20 transfer）

// 参数含义：

// initiator：发起这次闪电贷的人（一般是攻击者/策略合约的调用者）

// asset：借出的 token 地址

// amount：借出的本金

// fee：手续费

// data：附带数据（可以塞策略参数；我们 demo 里没用）

interface IFlashBorrower {
    /// @notice Called by lender after sending `amount` of `asset`
    /// @dev Borrower must return `amount + fee` to lender before returning.
    function onFlashLoan(
        address initiator,
        address asset,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external;
}

/// @title FlashLenderMock
/// @notice Minimal flash loan lender for learning. Sends funds then calls borrower, then checks repayment.
contract FlashLenderMock {
    MockERC20 public immutable asset;
    uint256 public immutable feeBps; // e.g. 5 = 0.05% (bps = 1/10000)

    error NotEnoughLiquidity(uint256 have, uint256 need);
    error RepayFailed(uint256 expectedBalance, uint256 actualBalance);

    event FlashLoan(address indexed borrower, uint256 amount, uint256 fee);

    constructor(MockERC20 _asset, uint256 _feeBps) {
        asset = _asset;
        feeBps = _feeBps;
    }

    function liquidity() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function flashLoan(
        IFlashBorrower borrower,
        uint256 amount,
        bytes calldata data
    ) external {
        uint256 balBefore = asset.balanceOf(address(this));
        if (balBefore < amount) revert NotEnoughLiquidity(balBefore, amount);

        uint256 fee = (amount * feeBps) / 10_000;

        // 1) Send loan
        asset.transfer(address(borrower), amount);

        // 2) Callback
        borrower.onFlashLoan(msg.sender, address(asset), amount, fee, data);

        // 3) Verify repay
        uint256 balAfter = asset.balanceOf(address(this));
        uint256 expected = balBefore + fee;
        if (balAfter < expected) revert RepayFailed(expected, balAfter);

        emit FlashLoan(address(borrower), amount, fee);
    }
}
