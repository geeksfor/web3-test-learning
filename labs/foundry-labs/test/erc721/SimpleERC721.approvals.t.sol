// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/erc721/SimpleERC721.sol";

contract SimpleERC721ApprovalsTest is Test {
    SimpleERC721 nft;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address op = address(0xA11BC);
    address stranger = address(0xA11B);

    uint256 tokenId = 1;

    function setUp() public {
        nft = new SimpleERC721();
        nft.mint(alice, 1);
    }

    function test_setApprovalForAll_true_emitsEvent_andSetsState() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(nft));
        emit SimpleERC721.ApprovalForAll(alice, op, true);
        nft.setApprovalForAll(op, true);

        // 检查授权状态是否生效
        assertTrue(nft.isApprovedForAll(alice, op));
    }

    function test_setApprovalForAll_false_emitsEvent_andClearsState() public {
        // 先授权 true，证明后续的 false 是“清除”而不是“本来就没有”
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(nft));
        emit SimpleERC721.ApprovalForAll(alice, op, true);
        nft.setApprovalForAll(op, true);

        // 再取消授权，校验事件与状态
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(nft));
        emit SimpleERC721.ApprovalForAll(alice, op, false);
        nft.setApprovalForAll(op, false);

        // 检查授权状态是否生效
        assertFalse(nft.isApprovedForAll(alice, op));
    }

    function test_setApprovalForAll_self_reverts() public {
        // 授权给自己会revert
        vm.prank(alice);
        vm.expectRevert(SimpleERC721.ApproveToSelf.selector);
        nft.setApprovalForAll(alice, true);
    }

    function test_approve_owner_setsGetApproved_andEmitsApproval() public {
        assertEq(nft.getApproved(tokenId), address(0));
        vm.prank(alice);
        vm.expectEmit(true, true, true, true, address(nft));
        emit SimpleERC721.Approval(alice, bob, tokenId);
        nft.approve(bob, tokenId);

        // 检查状态
        assertEq(nft.getApproved(tokenId), bob);
    }

    //operator 也能 approve（approvalForAll 的权限延伸）
    function test_approve_operator_setsGetApproved() public {
        vm.prank(alice);
        nft.setApprovalForAll(op, true);
        assertTrue(nft.isApprovedForAll(alice, op));

        vm.expectEmit(true, true, true, false, address(nft));
        emit SimpleERC721.Approval(alice, bob, tokenId);
        vm.prank(op);
        nft.approve(bob, tokenId);

        assertEq(nft.getApproved(tokenId), bob);
    }

    function test_approve_unauthorized_reverts() public {
        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(address(0), nft.getApproved(tokenId));
        vm.prank(stranger);
        vm.expectRevert(SimpleERC721.NotOwnerNorApproved.selector);
        nft.approve(bob, tokenId);
    }

    function test_transferFrom_byApproved_succeeds_andClearsApproval() public {
        assertEq(nft.ownerOf(tokenId), alice);
        vm.prank(alice);
        vm.expectEmit(true, true, true, false, address(nft));
        emit SimpleERC721.Approval(alice, bob, tokenId);
        nft.approve(bob, tokenId);
        assertEq(nft.getApproved(tokenId), bob);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true, address(nft));
        emit SimpleERC721.Transfer(alice, stranger, tokenId);
        nft.transferFrom(alice, stranger, tokenId);
        assertEq(stranger, nft.ownerOf(tokenId));
        assertEq(nft.getApproved(tokenId), address(0));
    }

    function test_approve_nonexistentToken_reverts() public {
        uint256 missingTokenId = 3;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleERC721.NonexistentToken.selector,
                missingTokenId
            )
        );
        nft.approve(bob, missingTokenId);
    }

    function test_getApproved_nonexistentToken_reverts() public {
        uint256 missingTokenId = type(uint256).max;
        // vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleERC721.NonexistentToken.selector,
                missingTokenId
            )
        );
        nft.getApproved(missingTokenId);
    }

    function test_approve_toOwner_reverts() public {
        assertEq(alice, nft.ownerOf(tokenId));

        vm.prank(alice);
        vm.expectRevert(SimpleERC721.ApproveToSelf.selector);
        nft.approve(alice, tokenId);

        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.getApproved(tokenId), address(0));
    }
}
