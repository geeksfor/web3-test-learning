// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/erc721/SimpleERC721.sol";

contract GoodReceiver is IERC721Receiver {
    event Received(address operator, address from, uint256 tokenId, bytes data);

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        emit Received(operator, from, tokenId, data);
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract BadReceiver {
    // 不实现 onERC721Received
}

contract SimpleERC721AuthTest is Test {
    SimpleERC721 nft;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address eve = address(0xA11B);
    address op = address(0xA11BC);

    function setUp() public {
        nft = new SimpleERC721();
        nft.mint(alice, 1);
    }

    // ========== transferFrom 正常：owner 直接转 ==========
    function test_transferFrom_success_byOwner() public {
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.balanceOf(bob), 0);

        vm.expectEmit(true, true, true, false);
        emit SimpleERC721.Transfer(alice, bob, 1);

        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);

        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 1);
        assertEq(nft.getApproved(1), address(0));
    }

    // ========== transferFrom revert：非 owner 且未授权 ==========
    function test_transferFrom_reverts_ifNotOwnerNorApproved() public {
        vm.expectRevert(SimpleERC721.NotOwnerNorApproved.selector);
        vm.prank(eve);
        nft.transferFrom(alice, bob, 1);
    }

    // ========== transferFrom 正常：approve 后由 approved 转 ==========
    function test_transferFrom_success_byApproved() public {
        // alice 授权给 eve（只针对 tokenId=1）
        vm.prank(alice);
        nft.approve(eve, 1);
        assertEq(nft.getApproved(1), eve);

        vm.prank(eve);
        nft.transferFrom(alice, bob, 1);

        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 1);

        // 关键：授权必须被清空
        assertEq(nft.getApproved(1), address(0));
    }

    // ========== transferFrom 正常：setApprovalForAll 后由 operator 转 ==========
    function test_transferFrom_success_byOperator() public {
        vm.prank(alice);
        nft.setApprovalForAll(op, true);
        assertTrue(nft.isApprovedForAll(alice, op));

        vm.prank(op);
        nft.transferFrom(alice, bob, 1);
        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 1);
        assertEq(nft.getApproved(1), address(0));
    }

    // ========== safeTransferFrom 正常：to 是 EOA ==========
    function test_safeTransferFrom_success_toEOA() public {
        vm.prank(alice);
        nft.safeTransferFrom(alice, bob, 1);
        assertEq(nft.ownerOf(1), bob);
    }

    // ========== safeTransferFrom 正常：to 是实现 receiver 的合约 ==========
    function test_safeTransferFrom_success_toGoodReceiver() public {
        GoodReceiver r = new GoodReceiver();
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(r), 1);
        assertEq(nft.ownerOf(1), address(r));
    }

    // ========== safeTransferFrom revert：to 是合约但未实现 receiver ==========
    function test_safeTransferFrom_reverts_toBadReceiver() public {
        BadReceiver r = new BadReceiver();
        vm.expectRevert(SimpleERC721.UnsafeRecipient.selector);
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(r), 1);
    }
}
