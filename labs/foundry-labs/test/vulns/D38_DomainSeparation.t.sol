// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {D38_DomainSeparationBad} from "../../src/vulns/D38_DomainSeparationBad.sol";
import {D38_DomainSeparationGood} from "../../src/vulns/D38_DomainSeparationGood.sol";

contract D38_DomainSeparation_Test is Test {
    uint256 ownerPk;
    address owner;

    address spender; // 调用 doAction 的人（msg.sender）

    function setUp() public {
        ownerPk = 0xA11CE;
        owner = vm.addr(ownerPk);

        spender = makeAddr("spender");
    }

    // -------------- helpers --------------
    function signBad(
        address _owner,
        address _spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal returns (bytes memory sig) {
        bytes32 h = keccak256(
            abi.encode(_owner, _spender, amount, nonce, deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", h)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function signGood(
        address verifyingContract,
        uint256 chainId,
        address _owner,
        address _spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal returns (bytes memory sig) {
        bytes32 h = keccak256(
            abi.encode(
                _owner,
                _spender,
                amount,
                nonce,
                deadline,
                chainId,
                verifyingContract
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", h)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    // -------------- BAD: 漏洞证明 --------------
    function test_bad_replay_on_other_contract_succeeds() public {
        D38_DomainSeparationBad a = new D38_DomainSeparationBad();
        D38_DomainSeparationBad b = new D38_DomainSeparationBad(); // 地址不同

        uint256 amount = 7;
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 days;

        // 在合约 A 上签名（但签名本身不绑定合约地址）
        bytes memory sig = signBad(owner, spender, amount, nonce, deadline);

        vm.prank(spender);
        a.doAction(owner, amount, nonce, deadline, sig);
        assertEq(a.counter(), amount);

        // ❌ 漏洞：同一份 sig 拿到合约 B 仍能用（因为 digest 不含 address(this)）
        vm.prank(spender);
        b.doAction(owner, amount, nonce, deadline, sig);
        assertEq(b.counter(), amount);
    }

    function test_bad_replay_after_chain_change_succeeds() public {
        D38_DomainSeparationBad c = new D38_DomainSeparationBad();

        uint256 amount = 5;
        uint256 nonce = 2;
        uint256 deadline = block.timestamp + 1 days;

        bytes memory sig = signBad(owner, spender, amount, nonce, deadline);

        vm.prank(spender);
        c.doAction(owner, amount, nonce, deadline, sig);
        assertEq(c.counter(), amount);

        // 模拟换链/分叉环境（Foundry 支持直接改 chainId）
        vm.chainId(999);

        // ❌ 漏洞：chainId 变了，sig 仍有效（digest 不包含 chainId）
        vm.prank(spender);
        c.doAction(
            owner,
            amount,
            3,
            deadline,
            signBad(owner, spender, amount, 3, deadline)
        );
        assertEq(c.counter(), amount + amount);
    }

    // -------------- GOOD: 修复验证 --------------
    function test_good_replay_on_other_contract_reverts() public {
        D38_DomainSeparationGood a = new D38_DomainSeparationGood();
        D38_DomainSeparationGood b = new D38_DomainSeparationGood();

        uint256 amount = 7;
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 days;

        uint256 cid = block.chainid;

        // 绑定合约 A 地址 + chainId 的签名
        bytes memory sigA = signGood(
            address(a),
            cid,
            owner,
            spender,
            amount,
            nonce,
            deadline
        );

        vm.prank(spender);
        a.doAction(owner, amount, nonce, deadline, sigA);
        assertEq(a.counter(), amount);

        // ✅ 修复：同签名拿到合约 B 必须失败（BadSig）
        vm.prank(spender);
        vm.expectRevert(D38_DomainSeparationGood.BadSig.selector);
        b.doAction(owner, amount, nonce, deadline, sigA);
    }

    function test_good_replay_after_chain_change_reverts() public {
        D38_DomainSeparationGood c = new D38_DomainSeparationGood();

        uint256 amount = 9;
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 days;

        uint256 cid = block.chainid;
        bytes memory sig = signGood(
            address(c),
            cid,
            owner,
            spender,
            amount,
            nonce,
            deadline
        );

        vm.prank(spender);
        c.doAction(owner, amount, nonce, deadline, sig);
        assertEq(c.counter(), amount);

        vm.chainId(777);

        // ✅ 修复：chainId 变了，旧签名必须失效
        vm.prank(spender);
        vm.expectRevert(D38_DomainSeparationGood.BadSig.selector);
        c.doAction(owner, amount, 2, deadline, sig);
    }

    function test_good_deadline_expired_reverts() public {
        D38_DomainSeparationGood c = new D38_DomainSeparationGood();

        uint256 amount = 1;
        uint256 nonce = 1;
        uint256 deadline = block.timestamp - 1; // 已过期

        bytes memory sig = signGood(
            address(c),
            block.chainid,
            owner,
            spender,
            amount,
            nonce,
            deadline
        );

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                D38_DomainSeparationGood.Expired.selector,
                block.timestamp,
                deadline
            )
        );
        c.doAction(owner, amount, nonce, deadline, sig);
    }
}
