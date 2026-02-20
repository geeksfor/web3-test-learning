// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D37_NonceReplayVuln.sol";
import "../../src/vulns/D37_NonceReplayFixed.sol";

contract D37_NonceReplay_Test is Test {
    // 用 Foundry 的私钥签名
    uint256 signerPk;
    address signer;

    address alice;

    function setUp() public {
        signerPk = 0xA11CE; // 任意私钥（测试里用）
        signer = vm.addr(signerPk);

        alice = makeAddr("alice");
    }

    function _signVuln(
        address to,
        uint256 amount
    ) internal view returns (bytes memory sig) {
        bytes32 msgHash = keccak256(abi.encodePacked(to, amount));
        bytes32 digest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _signFixed(
        address to,
        uint256 amount,
        uint256 nonce
    ) internal view returns (bytes memory sig) {
        bytes32 msgHash = keccak256(abi.encodePacked(to, amount, nonce));
        bytes32 digest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    /// @notice 漏洞复现：同一份签名被重复使用，余额翻倍
    function test_vuln_sameSignature_canBeReplayed() public {
        D37_NonceReplayVuln vuln = new D37_NonceReplayVuln(signer);
        uint256 amount = 100;
        bytes memory sig = _signVuln(alice, amount);

        vuln.claim(alice, amount, sig);
        assertEq(vuln.balanceOf(alice), 100);

        // 攻击：重放同一个签名
        vuln.claim(alice, amount, sig);
        assertEq(vuln.balanceOf(alice), 200);
    }

    /// @notice 修复验证：同 nonce 的签名只能用一次，第二次必须 revert
    function test_fixed_sameSignature_replay_reverts() public {
        D37_NonceReplayFixed fixedC = new D37_NonceReplayFixed(signer);

        uint256 amount = 100;
        uint256 nonce = 7;
        bytes memory sig = _signFixed(alice, amount, nonce);

        fixedC.claim(alice, amount, nonce, sig);
        assertEq(fixedC.balanceOf(alice), 100);

        // 重放：nonce 已用 => revert
        vm.expectRevert(
            abi.encodeWithSelector(
                D37_NonceReplayFixed.NonceUsed.selector,
                alice,
                nonce
            )
        );
        fixedC.claim(alice, amount, nonce, sig);

        // 状态不变
        assertEq(fixedC.balanceOf(alice), 100);
        assertTrue(fixedC.usedNonce(alice, nonce));
    }
}
