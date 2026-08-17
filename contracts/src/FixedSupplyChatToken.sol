// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @notice Fixed-supply, permit-enabled token template for TinyAI chat payments.
/// @dev There is no owner and no mint function after construction.
contract FixedSupplyChatToken is ERC20, ERC20Permit {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;
    uint16 public constant TREASURY_BPS = 6_500;
    uint16 public constant LIQUIDITY_BPS = 2_000;
    uint16 public constant COMMUNITY_BPS = 1_500;

    error ZeroRecipient();

    constructor(string memory name_, string memory symbol_, address treasury, address liquidity, address community)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        if (treasury == address(0) || liquidity == address(0) || community == address(0)) revert ZeroRecipient();
        _mint(treasury, MAX_SUPPLY * TREASURY_BPS / 10_000);
        _mint(liquidity, MAX_SUPPLY * LIQUIDITY_BPS / 10_000);
        _mint(community, MAX_SUPPLY * COMMUNITY_BPS / 10_000);
    }
}
