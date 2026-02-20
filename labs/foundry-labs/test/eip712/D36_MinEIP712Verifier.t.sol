// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../src/eip712/D36_MinEIP712Verifier.sol";

contract D36_MinEIP712Verifier_Test is Test {
    D36_MinEIP712Verifier verifier;

    uint256 signerPk; // 给一个固定私钥（测试专用）
    address signer; // 从私钥推导出地址

    address bob = address(0xB0B);

    function setUp() public {
        verifier = new D36_MinEIP712Verifier("D36-MinEIP712", "1");

        // Forge 的签名：用私钥生成地址
        signerPk = 0xA11CE; // 你也可以换成任意 uint256
        signer = vm.addr(signerPk);
    }

    function test_verify_ok() public {
        D36_MinEIP712Verifier.Mail memory m = D36_MinEIP712Verifier.Mail({
            to: bob,
            amount: 123,
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = verifier.digestMail(m);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        bool ok = verifier.verify(signer, m, v, r, s);
        assertTrue(ok);
    }

    function test_verify_fails_if_deadline_expired() public {
        D36_MinEIP712Verifier.Mail memory m = D36_MinEIP712Verifier.Mail({
            to: bob,
            amount: 123,
            nonce: 1,
            deadline: block.timestamp + 1
        });

        bytes32 digest = verifier.digestMail(m);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.warp(block.timestamp + 2); // 超过 deadline
        bool ok = verifier.verify(signer, m, v, r, s);
        assertFalse(ok);
    }

    function test_verify_fails_if_nonce_changed() public {
        D36_MinEIP712Verifier.Mail memory m = D36_MinEIP712Verifier.Mail({
            to: bob,
            amount: 123,
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = verifier.digestMail(m);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        // 验签时把 nonce 改掉 => structHash 变了 => digest 变了 => recover 失败
        D36_MinEIP712Verifier.Mail memory m2 = D36_MinEIP712Verifier.Mail({
            to: bob,
            amount: 123,
            nonce: 2,
            deadline: m.deadline
        });

        bool ok = verifier.verify(signer, m2, v, r, s);
        assertFalse(ok);
    }

    function test_verify_fails_if_expectedSigner_wrong() public {
        D36_MinEIP712Verifier.Mail memory m = D36_MinEIP712Verifier.Mail({
            to: bob,
            amount: 123,
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = verifier.digestMail(m);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        address attacker = address(0xBAD);
        bool ok = verifier.verify(attacker, m, v, r, s);
        assertFalse(ok);
    }
}
