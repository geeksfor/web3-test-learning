// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract D36_MinEIP712Verifier {
    // --- EIP-712 domain ---
    bytes32 public constant EIP712DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public immutable NAME_HASH;
    bytes32 public immutable VERSION_HASH;

    // --- Typed data: Mail ---
    // 注意：字段顺序必须严格一致
    bytes32 public constant MAIL_TYPEHASH =
        keccak256(
            "Mail(address to,uint256 amount,uint256 nonce,uint256 deadline)"
        );

    struct Mail {
        address to;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
    }

    constructor(string memory name, string memory version) {
        NAME_HASH = keccak256(bytes(name));
        VERSION_HASH = keccak256(bytes(version));

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                NAME_HASH,
                VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    function hashMail(Mail memory m) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(MAIL_TYPEHASH, m.to, m.amount, m.nonce, m.deadline)
            );
    }

    function digestMail(Mail memory m) public view returns (bytes32) {
        bytes32 structHash = hashMail(m);
        return
            keccak256(
                abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
            );
    }

    function verify(
        address expectedSigner,
        Mail memory m,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public view returns (bool) {
        // 示例里顺手加一个 deadline 约束（真实业务很常见）
        if (block.timestamp > m.deadline) return false;

        bytes32 digest = digestMail(m);
        address recovered = ecrecover(digest, v, r, s);
        return recovered == expectedSigner && recovered != address(0);
    }
}
