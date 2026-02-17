// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice 可控 Oracle：返回 “1 COL 值多少 DEBT”，WAD=1e18 精度

contract D22_MockOracle {
    uint256 public price; // DEBT per 1 COL, scaled by 1e18
    address public owner;

    event PriceUpdated(uint256 newPrice);

    constructor(uint256 initialPrice) {
        owner = msg.sender;
        price = initialPrice;
        emit PriceUpdated(initialPrice);
    }

    function setPrice(uint256 newPrice) external {
        require(msg.sender == owner, "NOT_OWNER");
        price = newPrice;
        emit PriceUpdated(newPrice);
    }

    function getPrice() external view returns (uint256) {
        return price;
    }
}
