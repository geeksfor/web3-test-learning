// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @notice 漏洞点：签名只覆盖 (to, amount)，没有 nonce/deadline/已用标记 => 同一签名可重复调用
contract D37_NonceReplayVuln {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    error InvalidSignature();

    address public immutable signer; // 离线签名者（例如后台/运营/桥的验证者）

    mapping(address => uint256) public balanceOf;

    constructor(address _signer) {
        signer = _signer;
    }

    function _hash(address to, uint256 amount) internal pure returns (bytes32) {
        // 漏洞：没有 nonce
        return keccak256(abi.encodePacked(to, amount));
    }

    function claim(address to, uint256 amount, bytes calldata sig) external {
        bytes32 digest = _hash(to, amount).toEthSignedMessageHash();
        address recovered = ECDSA.recover(digest, sig);
        if (recovered != signer) revert InvalidSignature();

        // 发放/铸币/记账（这里用简单记账模拟）
        balanceOf[to] += amount;
    }
}
