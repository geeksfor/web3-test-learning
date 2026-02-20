// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @notice 修复点：签名覆盖 (to, amount, nonce)，并记录 usedNonce => 同一签名只能用一次
contract D37_NonceReplayFixed {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    error InvalidSignature();
    error NonceUsed(address to, uint256 nonce);

    address public immutable signer;

    mapping(address => uint256) public balanceOf;

    // 这里用 “每个领取地址 to 的 nonce 是否已用”
    mapping(address => mapping(uint256 => bool)) public usedNonce;

    constructor(address _signer) {
        signer = _signer;
    }

    function _hash(
        address to,
        uint256 amount,
        uint256 nonce
    ) internal pure returns (bytes32) {
        // ✅ 修复：加入 nonce（也可加入 chainid / address(this) 做域隔离）
        return keccak256(abi.encodePacked(to, amount, nonce));
    }

    function claim(
        address to,
        uint256 amount,
        uint256 nonce,
        bytes calldata sig
    ) external {
        if (usedNonce[to][nonce]) revert NonceUsed(to, nonce);

        bytes32 digest = _hash(to, amount, nonce).toEthSignedMessageHash();
        address recovered = ECDSA.recover(digest, sig);
        if (recovered != signer) revert InvalidSignature();

        // ✅ 先标记已用，再发放（遵循 CEI 思路）
        usedNonce[to][nonce] = true;
        balanceOf[to] += amount;
    }
}
