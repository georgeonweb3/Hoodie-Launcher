// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenLauncher} from "./TokenLauncher.sol";

/// @title LauncherFactory
/// @notice The "token launcher launcher" itself. Deploys TokenLauncher
///         instances — each one is a fully independent token launcher that
///         anyone can point people at, with its own fee and LP-lock terms —
///         but every single one is wired to the same immutable $HOODIE
///         address at birth and can never be reconfigured to point anywhere
///         else. This is the piece that makes "launching a token launcher
///         as easy as launching a token" literal: one call, one launcher,
///         rule enforced by construction.
contract LauncherFactory {
    /// @notice $HOODIE. Set once at factory deployment. Every launcher this
    ///         factory ever creates inherits this exact address — there is
    ///         no parameter on createLauncher() that can override it.
    address public immutable hoodie;

    address[] public allLaunchers;
    mapping(address => address) public launcherCreator;

    event LauncherCreated(
        address indexed launcher, address indexed creator, uint16 feeBps, address feeRecipient, uint16 lpBurnBps, string name
    );

    constructor(address hoodie_) {
        hoodie = hoodie_;
    }

    function allLaunchersCount() external view returns (uint256) {
        return allLaunchers.length;
    }

    function getAllLaunchers() external view returns (address[] memory) {
        return allLaunchers;
    }

    /// @notice Deploy a new, independently configured token launcher.
    /// @param feeBps Fee (bps) this launcher takes from the HOODIE side of
    ///        every launch made through it. Hard-capped at 10% inside
    ///        TokenLauncher itself, regardless of what's passed here.
    /// @param feeRecipient Where that fee goes.
    /// @param lpBurnBps Share of LP (bps) permanently burned on every launch
    ///        made through this launcher. 10_000 = every launch is fully
    ///        rug-proof by construction.
    /// @param name Display name for this launcher.
    function createLauncher(uint16 feeBps, address feeRecipient, uint16 lpBurnBps, string calldata name)
        external
        returns (address launcher)
    {
        TokenLauncher newLauncher = new TokenLauncher(hoodie, feeBps, feeRecipient, lpBurnBps, name);
        launcher = address(newLauncher);

        allLaunchers.push(launcher);
        launcherCreator[launcher] = msg.sender;

        emit LauncherCreated(launcher, msg.sender, feeBps, feeRecipient, lpBurnBps, name);
    }
}
