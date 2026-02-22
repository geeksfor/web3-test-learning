// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20View {
    function balanceOf(address) external view returns (uint256);

    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);
}
