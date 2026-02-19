// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILZReceiver {
    function lzReceive(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload,
        bytes32 messageId
    ) external;
}
