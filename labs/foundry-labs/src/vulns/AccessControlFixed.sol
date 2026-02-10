// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AccessControlFixed {
    address public owner;
    address public treasury;
    uint256 public feeBps;
    bool public paused;

    uint256 public feesAccrued;

    event TreasuryChanged(
        address indexed oldTreasury,
        address indexed newTreasury
    );
    event FeeChanged(uint256 oldFeeBps, uint256 newFeeBps);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event Paid(address indexed payer, uint256 amountIn, uint256 fee);
    event FeesWithdrawn(address indexed to, uint256 amount);

    error NotOwner(address caller);
    error InvalidTreasury();
    error InvalidFeeBps(uint256 feeBps);
    error PausedError();
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    constructor(address _treasury, uint256 _feeBps) {
        owner = msg.sender;
        treasury = _treasury;
        feeBps = _feeBps;
        paused = false;
    }

    // ✅ FIXED: all admin functions guarded
    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert InvalidTreasury();
        address old = treasury;
        treasury = newTreasury;
        emit TreasuryChanged(old, newTreasury);
    }

    function setFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > 1000) revert InvalidFeeBps(newFeeBps);
        uint256 old = feeBps;
        feeBps = newFeeBps;
        emit FeeChanged(old, newFeeBps);
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function withdrawFees() external onlyOwner {
        uint256 amount = feesAccrued;
        feesAccrued = 0;

        (bool ok, ) = treasury.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit FeesWithdrawn(treasury, amount);
    }

    function pay() external payable {
        if (paused) revert PausedError();
        uint256 fee = (msg.value * feeBps) / 10_000;
        feesAccrued += fee;
        emit Paid(msg.sender, msg.value, fee);
    }

    receive() external payable {}
}
