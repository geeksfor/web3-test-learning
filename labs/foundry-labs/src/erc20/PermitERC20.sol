// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract PermitERC20 is ERC20, ERC20Permit {
    constructor(
        string memory name_,
        string memory symbol_
    )
        ERC20(name_, symbol_)
        ERC20Permit(name_) // EIP-712 domain 的 name
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
