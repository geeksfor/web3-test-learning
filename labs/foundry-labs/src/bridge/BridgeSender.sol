// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../mocks/lz/MockLZEndpoint.sol";

contract BridgeSender {
    MockLZEndpoint public immutable endpoint;

    constructor(MockLZEndpoint _endpoint) {
        endpoint = _endpoint;
    }

    function bridge(
        uint16 dstChainId,
        address dstApp,
        address to,
        uint256 amount
    ) external {
        bytes memory payload = abi.encode(to, amount);
        endpoint.send(dstChainId, dstApp, payload);
    }
}
