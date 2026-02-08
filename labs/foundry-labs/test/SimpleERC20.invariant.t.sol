// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../src/SimpleERC20.sol";

contract ERC20Handler is Test {
    SimpleERC20 public token;
    address public owner;

    // 地址池（固定几个人，避免随机地址带来不可控情况）
    address[] public users;

    // ghost state
    uint256 public mintedSum;
    uint256 public burnedSum;

    constructor(SimpleERC20 _token, address _owner) {
        token = _token;
        owner = _owner;
        users.push(address(0xA11CE));
        users.push(address(0xB0B));
        users.push(address(0xA111CE));
        users.push(address(0xB0BCE));
    }

    function _pickUser(uint256 seed) internal view returns (address) {
        return users[seed % users.length];
    }

    // 1) mint：用 mintOnlyOwner（会更新 totalSupply）
    function mint(uint256 toSeed, uint256 amount) external {
        address to = _pickUser(toSeed);
        amount = bound(amount, 0, 1e24); // 控制规模，避免跑得慢/溢出风险

        vm.prank(owner);
        // token.mintOnlyOwner(to, amount);
        token.mint(to, amount);

        uint256 bal = token.balanceOf(to);
        emit log_named_uint("balanceOf(to)", bal);
        emit log_named_uint("totalSupply", token.totalSupply());

        mintedSum += amount;
    }

    // 2) burn：burn 自己（amount 必须 <= balance）
    function burn(uint256 whoSeed, uint256 amount) external {
        address who = _pickUser(whoSeed);
        uint256 bal = token.balanceOf(who);
        if (bal == 0) return;

        amount = bound(amount, 0, bal);

        vm.prank(who);
        token.burn(amount);

        burnedSum += amount;
    }

    // 3) burnFrom：spender burn tokenOwner（需要 allowance + balance）
    function burnFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 amount
    ) external {
        address tokenOwner = _pickUser(ownerSeed);
        address spender = _pickUser(spenderSeed);
        if (tokenOwner == spender) return;

        uint256 bal = token.balanceOf(tokenOwner);
        if (bal == 0) return;

        // 给 spender 授权（随机授一个 <= bal 的额度）
        uint256 approveAmt = bound(amount, 0, bal);
        vm.prank(tokenOwner);
        token.approve(spender, approveAmt);

        if (approveAmt == 0) return;

        // burnFrom 的 amount 不能超过 allowance & balance
        uint256 allowed = token.allowance(tokenOwner, spender);
        uint256 maxBurn = bal < allowed ? bal : allowed;
        if (maxBurn == 0) return;

        uint256 burnAmt = bound(amount, 0, maxBurn);
        vm.prank(spender);
        token.burnFrom(tokenOwner, burnAmt);

        burnedSum += burnAmt;
    }

    // 4) 普通 transfer（不影响 supply，但有助于打乱余额分布）
    function transfer(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 amount
    ) external {
        address from = _pickUser(fromSeed);
        address to = _pickUser(toSeed);
        if (from == to) return;

        uint256 bal = token.balanceOf(from);
        if (bal == 0) return;

        amount = bound(amount, 0, bal);

        vm.prank(from);
        token.transfer(to, amount);
    }
}

contract SimpleERC20InvariantTest is StdInvariant, Test {
    SimpleERC20 token;
    ERC20Handler handler;

    address owner = address(this);

    function setUp() public {
        token = new SimpleERC20();

        // 构造 handler
        handler = new ERC20Handler(token, owner);

        // 让 invariant 引擎只随机调用 handler
        targetContract(address(handler));

        // // （可选）限制只调用指定函数，减少噪声
        // bytes4;
        // selectors[0] = ERC20Handler.mint.selector;
        // selectors[1] = ERC20Handler.burn.selector;
        // selectors[2] = ERC20Handler.burnFrom.selector;
        // selectors[3] = ERC20Handler.transfer.selector;

        // targetSelector(
        //     FuzzSelector({addr: address(handler), selectors: selectors})
        // );
    }

    // Invariant 1：totalSupply 必须等于 minted-burned
    function invariant_totalSupply_matches_minted_minus_burned() public view {
        assertEq(
            token.totalSupply(),
            handler.mintedSum() - handler.burnedSum()
        );
    }

    // Invariant 2：burnedSum 永远不可能超过 mintedSum
    function invariant_burned_le_minted() public view {
        assertLe(handler.burnedSum(), handler.mintedSum());
    }
}
