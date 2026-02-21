// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract D38_DomainSeparationGood {
    error Expired(uint256 nowTs, uint256 deadline);
    error NonceUsed(address owner, uint256 nonce);
    error BadSig();

    mapping(address => mapping(uint256 => bool)) public usedNonce;

    // 业务：用签名授权执行一次“动作”（这里只做事件/计数，方便测试）
    uint256 public counter;

    function doAction(
        address owner,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata sig
    ) external {
        if (block.timestamp > deadline)
            revert Expired(block.timestamp, deadline);
        if (usedNonce[owner][nonce]) revert NonceUsed(owner, nonce);

        bytes32 digest = _digestGood(
            owner,
            msg.sender,
            amount,
            nonce,
            deadline
        );

        if (!_verify(owner, digest, sig)) revert BadSig();

        usedNonce[owner][nonce] = true;
        counter += amount;
    }

    // ✅ 修复：digest 加入 block.chainid + address(this)，实现域隔离
    function _digestGood(
        address owner,
        address spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 h = keccak256(
            abi.encode(
                owner,
                spender,
                amount,
                nonce,
                deadline,
                block.chainid,
                address(this)
            )
        );
        return
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }

    function _verify(
        address signer,
        bytes32 digest,
        bytes calldata sig
    ) internal pure returns (bool) {
        if (sig.length != 65) return false;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v < 27) v += 27;
        address recovered = ecrecover(digest, v, r, s);
        return recovered == signer && recovered != address(0);
    }
}
