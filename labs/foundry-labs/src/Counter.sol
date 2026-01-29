// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract Counter {
    uint256 public number;

    constructor(uint256 _init) {
        number = _init;
    }

    function setNumber(uint256 newNumber) external {
        number = newNumber;
    }

    function increment() external {
        number += 1;
    }
}
