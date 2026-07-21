// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title LaunchedToken
/// @notice The ERC20 created by TokenLauncher.launchToken(). Fixed supply,
///         minted entirely to the launcher at construction so it can be
///         atomically seeded into the $HOODIE pair in the same transaction.
///         No owner, no mint function, no blacklist — nothing a launcher
///         creator could later abuse. What you deploy is what exists forever.
contract LaunchedToken is ERC20 {
    constructor(string memory name_, string memory symbol_, uint256 totalSupply_, address mintTo)
        ERC20(name_, symbol_)
    {
        _mint(mintTo, totalSupply_);
    }
}
