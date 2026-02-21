// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract D40_ParamInjectionVuln {
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public nonces;

    error BadSig();
    error Expired();

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    // 漏洞：签名只承诺了 from/nonce/deadline，没承诺 to/amount
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

        bytes32 digest = keccak256(
            abi.encodePacked("D40_TRANSFER_V1", from, nonce, deadline)
        );

        address recovered = ecrecover(toEthSignedMessageHash(digest), v, r, s);
        if (recovered != from) revert BadSig();

        // 成功后 nonce++
        nonces[from] = nonce + 1;

        // 执行时 to/amount 是“外部参数”，不受签名约束 → 可注入
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function toEthSignedMessageHash(bytes32 h) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }
}
