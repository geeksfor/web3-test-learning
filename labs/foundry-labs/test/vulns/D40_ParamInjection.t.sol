// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D40_ParamInjectionVuln.sol";
import "../../src/vulns/D40_ParamInjectionFixed.sol";

contract D40_ParamInjection_Test is Test {
    D40_ParamInjectionVuln vuln;
    D40_ParamInjectionFixed fixedC;

    uint256 alicePk;
    address alice;
    address bob;
    address attacker;

    function setUp() public {
        vuln = new D40_ParamInjectionVuln();
        fixedC = new D40_ParamInjectionFixed();

        alicePk = 0xA11CE;
        alice = vm.addr(alicePk);

        bob = makeAddr("bob");
        attacker = makeAddr("attacker");

        vuln.mint(alice, 1000);
        fixedC.mint(alice, 1000);
    }

    function test_vuln_paramInjection_stealsMoreAndChangesRecipient() public {
        // Alice 线下“签名”一份授权（漏洞：签名不含 to/amount）
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = vuln.nonces(alice);

        bytes32 digest = keccak256(
            abi.encodePacked("D40_TRANSFER_V1", alice, nonce, deadline)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            toEthSignedMessageHash(digest)
        );

        // 攻击者注入参数：把 to 改成 attacker，把 amount 改大
        vuln.transferWithSig(alice, attacker, 900, deadline, v, r, s);

        assertEq(vuln.balanceOf(attacker), 900);
        assertEq(vuln.balanceOf(alice), 1000 - 900);
    }

    function test_fixed_paramInjection_failsBecauseToAmountAreSigned() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = fixedC.nonces(alice);

        // Alice 正确签名（包含 to/amount + domain）
        address intendedTo = bob;
        uint256 intendedAmount = 100;

        bytes32 digest = keccak256(
            abi.encode(
                "D40_TRANSFER_V1",
                block.chainid,
                address(fixedC),
                alice,
                intendedTo,
                intendedAmount,
                nonce,
                deadline
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            toEthSignedMessageHash(digest)
        );

        // 攻击者尝试注入：改 to/amount
        vm.expectRevert(D40_ParamInjectionFixed.BadSig.selector);
        fixedC.transferWithSig(alice, attacker, 900, deadline, v, r, s);

        // 正常执行：必须和签名参数一致
        fixedC.transferWithSig(
            alice,
            intendedTo,
            intendedAmount,
            deadline,
            v,
            r,
            s
        );

        assertEq(fixedC.balanceOf(bob), 100);
        assertEq(fixedC.balanceOf(alice), 900);
    }

    function toEthSignedMessageHash(bytes32 h) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }
}
