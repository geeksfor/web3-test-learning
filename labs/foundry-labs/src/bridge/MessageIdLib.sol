// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library MessageIdLib {
    function compute(
        uint16 srcChainId,
        address srcApp,
        uint16 dstChainId,
        address dstApp,
        uint64 nonce,
        bytes memory payload
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    "MSG_V1",
                    srcChainId,
                    srcApp,
                    dstChainId,
                    dstApp,
                    nonce,
                    keccak256(payload)
                )
            );
    }
}
