// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/vulns/D17_UUPS_OZ.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract D17_OZ_UUPS_OnlyProxy_Test is Test {
    address alice = address(0xA11CE);
    address attacker = address(0xB0B);

    function test_oz_proxy_atomic_init_and_initializer_only_once() public {
        // 1) 部署 impl（已 _disableInitializers，impl 上不能 initialize）
        D17_UUPS_OZ impl = new D17_UUPS_OZ();

        // 2) ✅ OZ 5.5 强制要求 initData 非空：构造时原子初始化
        bytes memory initData = abi.encodeCall(D17_UUPS_OZ.initialize, (alice));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // 3) 通过 proxy 地址当作逻辑合约交互（状态在 proxy）
        D17_UUPS_OZ proxied = D17_UUPS_OZ(address(proxy));
        assertEq(proxied.owner(), alice);

        // 4) initializer 只能一次：再次 initialize 必须 revert
        vm.prank(attacker);
        vm.expectRevert(); // 通常是 InvalidInitialization()
        proxied.initialize(attacker);
        // owner 不变
        assertEq(proxied.owner(), alice);

        // 5) 证明 impl 自身确实无法 initialize（disableInitializers 生效）
        vm.prank(alice);
        vm.expectRevert(); // InvalidInitialization()
        impl.initialize(alice);

        // impl.initialize(attacker);
    }

    function test_uups_onlyProxy_upgrade_flow() public {
        // V1 impl
        D17_UUPS_OZ implV1 = new D17_UUPS_OZ();

        // proxy + init(owner=alice)
        bytes memory initData = abi.encodeCall(D17_UUPS_OZ.initialize, (alice));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implV1), initData);
        D17_UUPS_OZ proxied = D17_UUPS_OZ(address(proxy));
        assertEq(proxied.owner(), alice);

        // V2 impl（用同一个合约类型即可，演示升级“换地址”）
        D17_UUPS_OZ implV2 = new D17_UUPS_OZ();

        // 1) ❌ 直接在 impl 地址调用 upgradeToAndCall：必须失败（onlyProxy 语义）
        vm.prank(alice);
        vm.expectRevert(); // 通常是 UUPSUnauthorizedCallContext()
        implV1.upgradeToAndCall(address(implV2), "");

        // 2) ✅ 通过 proxy 调用 upgradeToAndCall：成功（delegatecall 上下文）
        vm.prank(alice);
        proxied.upgradeToAndCall(address(implV2), "");

        // 3) 升级后状态仍在（storage 在 proxy，不会丢）
        assertEq(proxied.owner(), alice);
    }

    function test_upgrade_rejected_for_non_owner() public {
        D17_UUPS_OZ implV1 = new D17_UUPS_OZ();
        bytes memory initData = abi.encodeCall(D17_UUPS_OZ.initialize, (alice));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implV1), initData);
        D17_UUPS_OZ proxied = D17_UUPS_OZ(address(proxy));

        D17_UUPS_OZ implV2 = new D17_UUPS_OZ();

        vm.prank(attacker);
        vm.expectRevert(D17_UUPS_OZ.NotOwner.selector);
        proxied.upgradeToAndCall(address(implV2), "");
    }
}
