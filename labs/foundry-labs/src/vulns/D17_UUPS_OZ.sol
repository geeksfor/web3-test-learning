// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract D17_UUPS_OZ is Initializable, UUPSUpgradeable {
    address public owner;

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        // 先不实现这个函数，否则无法直接调用该合约的initialize函数，需要引入proxy概念
        _disableInitializers();
    }

    // 训练版：先不 _disableInitializers()，否则你无法在“非 proxy”场景调试
    // 上生产再加：constructor(){ _disableInitializers(); }
    function initialize(address _owner) external initializer {
        owner = _owner;
        // __UUPSUpgradeable_init();
    }

    // UUPS 升级权限控制：谁能升级？
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
