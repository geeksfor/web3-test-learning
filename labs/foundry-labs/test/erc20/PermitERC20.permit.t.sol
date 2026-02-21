// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {PermitERC20} from "../../src/erc20/PermitERC20.sol";

contract PermitERC20_PermitTest is Test {
    PermitERC20 token;

    // 用 Foundry 的私钥/地址对，方便签名
    uint256 ownerPk;
    address owner;

    address spender = makeAddr("spender");

    function setUp() public {
        token = new PermitERC20("PermitToken", "PTK");

        ownerPk = 0xA11CE; // 随便给一个私钥（测试用）
        owner = vm.addr(ownerPk);

        token.mint(owner, 1_000 ether);
    }

    function test_permit_success_setsAllowance_andIncrementsNonce() public {
        uint256 value = 123 ether;
        uint256 deadline = block.timestamp + 1 days;

        uint256 nonceBefore = token.nonces(owner);

        // 1) 计算 EIP-712 digest（ERC20Permit 提供）
        bytes32 digest = _permitDigest(
            owner,
            spender,
            value,
            nonceBefore,
            deadline
        );

        // 2) 链下签名：拿到 (v,r,s)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        // 3) 任意人提交签名上链调用 permit（这里我们直接本测试合约调用）
        token.permit(owner, spender, value, deadline, v, r, s);

        // 4) 断言：allowance 生效、nonce +1
        assertEq(token.allowance(owner, spender), value);
        assertEq(token.nonces(owner), nonceBefore + 1);
    }

    function test_permit_replay_sameSignature_reverts_dueToNonce() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 days;

        uint256 nonceBefore = token.nonces(owner);
        bytes32 digest = _permitDigest(
            owner,
            spender,
            value,
            nonceBefore,
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        // 第一次成功
        token.permit(owner, spender, value, deadline, v, r, s);
        assertEq(token.allowance(owner, spender), value);

        // 第二次用同一签名重放：因为 nonce 已变，会失败
        // OZ 的错误信息可能随版本变化（可能是 ECDSA InvalidSignature / ERC2612InvalidSigner 等）
        // 所以这里用“泛化断言”：只要 revert 即可
        vm.expectRevert();
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    function test_permit_deadlineExpired_reverts() public {
        uint256 value = 5 ether;
        uint256 deadline = block.timestamp + 10; // 很短

        uint256 nonceBefore = token.nonces(owner);
        bytes32 digest = _permitDigest(
            owner,
            spender,
            value,
            nonceBefore,
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        // 时间推进到过期之后
        vm.warp(deadline + 1);

        vm.expectRevert();
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    // --- helpers ---
    function _permitDigest(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _nonce,
        uint256 _deadline
    ) internal view returns (bytes32) {
        // ERC20Permit 实现了 EIP-712：
        // digest = keccak256("\x19\x01" || DOMAIN_SEPARATOR || structHash)
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                _owner,
                _spender,
                _value,
                _nonce,
                _deadline
            )
        );

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();

        return
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator, structHash)
            );
    }
}
