// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/erc721/SimpleERC721.sol";

contract ERC721MintRandomHandler is Test {
    SimpleERC721 public nft;
    address public target;

    // ghost state：记录哪些 tokenId 已经成功 mint 过
    mapping(uint256 => bool) public minted;
    uint256 public mintedCount;

    constructor(SimpleERC721 _nft, address _target) {
        nft = _nft;
        target = _target;
    }

    // fuzzer 会随机多次调用，并随机给 tokenId
    function mintRandom(uint256 tokenId) external {
        tokenId = bound(tokenId, 1, 1_000_000);
        vm.assume(!minted[tokenId]);
        nft.mint(target, tokenId);
        minted[tokenId] = true;
        mintedCount++;
    }
}

contract SimpleERC721Test is Test {
    SimpleERC721 nft;
    ERC721MintRandomHandler handler;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        nft = new SimpleERC721();
        handler = new ERC721MintRandomHandler(nft, alice);
        targetContract(address(handler));
    }

    // 1) mint 成功：ownerOf / balanceOf / Transfer 事件
    function test_mint_success_updatesOwnerAndBalance_andEmitsTransfer()
        public
    {
        uint256 tokenId = 1;

        // 事件断言：Transfer(0x0 -> alice, tokenId)
        vm.expectEmit(true, true, true, true);
        emit SimpleERC721.Transfer(address(0), alice, tokenId);

        nft.mint(alice, tokenId);

        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.balanceOf(alice), 1);
    }

    // 2) mint 到 0 地址：revert
    function test_mint_reverts_ifToIsZeroAddress() public {
        uint256 tokenId = 1;

        vm.expectRevert(SimpleERC721.ZeroAddress.selector);
        nft.mint(address(0), tokenId);
    }

    // 3) tokenId 重复 mint：revert
    function test_mint_reverts_ifTokenAlreadyMinted() public {
        uint256 tokenId = 1;

        vm.expectEmit(true, true, true, true);
        emit SimpleERC721.Transfer(address(0), alice, tokenId);

        nft.mint(alice, tokenId);

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleERC721.TokenAlreadyMinted.selector,
                tokenId
            )
        );
        nft.mint(bob, tokenId);
    }

    // 4) ownerOf：token 不存在必须 revert
    function test_ownerOf_reverts_ifNonexistentToken() public {
        uint256 tokenId = 999;

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleERC721.NonexistentToken.selector,
                tokenId
            )
        );
        nft.ownerOf(tokenId);
    }

    // 5) balanceOf：owner == 0 地址必须 revert
    function test_balanceOf_reverts_ifOwnerIsZeroAddress() public {
        vm.expectRevert(SimpleERC721.ZeroAddress.selector);
        nft.balanceOf(address(0));
    }

    // 6) 多次 mint：balance 累加（顺手验证）
    function test_balanceOf_accumulates_withMultipleMints() public {
        nft.mint(alice, 1);
        nft.mint(alice, 2);
        nft.mint(alice, 3);

        assertEq(nft.balanceOf(alice), 3);
        assertEq(nft.ownerOf(2), alice);
    }

    /// @dev fuzz: 随机 to/tokenId，mint 后 ownerOf(tokenId) 必须是 to
    /// 注意：排除 to=0 地址；另外可以约束 tokenId 范围避免极端值（可选）
    function testFuzz_mint_ownerOf_isTo(address to, uint256 tokenId) public {
        // 1) 排除 0 地址（否则 mint 会 revert，fuzz 会把它当失败）
        vm.assume(to != address(0));

        // 2) （可选）限制 tokenId 范围，避免一些极端边界导致调试麻烦
        tokenId = bound(tokenId, 1, type(uint128).max);

        nft.mint(to, tokenId);
        assertEq(nft.ownerOf(tokenId), to);
    }

    // invariant：合约余额必须等于 handler 成功 mint 次数
    function invariant_balanceEqualsSuccessfulMints() public view {
        assertEq(nft.balanceOf(alice), handler.mintedCount());
    }
}
