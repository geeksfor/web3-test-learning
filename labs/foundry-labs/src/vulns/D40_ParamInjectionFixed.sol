// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract D40_ParamInjectionFixed {
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public nonces;

    error BadSig();
    error Expired();

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transferWithSig(
        address from,
        address to,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) revert Expired();

        uint256 nonce = nonces[from];

        // ✅ 修复：把执行关键参数全部签进去 + domain separation
        bytes32 digest = keccak256(
            abi.encode(
                "D40_TRANSFER_V1",
                block.chainid,
                address(this),
                from,
                to,
                amount,
                nonce,
                deadline
            )
        );

        address recovered = ecrecover(toEthSignedMessageHash(digest), v, r, s);
        if (recovered != from) revert BadSig();

        nonces[from] = nonce + 1;

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function toEthSignedMessageHash(bytes32 h) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }
}
