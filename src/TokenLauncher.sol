// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LaunchedToken} from "./LaunchedToken.sol";
import {HoodiePair} from "./HoodiePair.sol";

/// @title TokenLauncher
/// @notice One "token launcher" as described in the bounty. Deployed by
///         LauncherFactory, never deployed directly, so every instance is
///         guaranteed to come from the same audited creation path.
///
///         Anyone can call launchToken() to create a brand-new ERC20 and, in
///         the SAME transaction, seed it into a fresh HoodiePair against
///         $HOODIE. There is no code path that creates a token without also
///         creating its HOODIE pool — that's what "immutable rule" means
///         here: it's not a policy, it's the only function that exists.
///
///         A slice of every launch's HOODIE contribution can optionally go
///         to `feeRecipient` (e.g. the launcher's creator, or burned) — this
///         is what lets a "launcher launcher" support many differently
///         configured launchers (different fees, different LP-lock terms)
///         while every single one of them still enforces the HOODIE rule.
contract TokenLauncher is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice $HOODIE. Set once at deployment by the factory, immutable
    ///         forever after — this is the actual enforcement mechanism.
    IERC20 public immutable hoodie;

    /// @notice Fee taken from the HOODIE side of every launch, in basis
    ///         points (100 = 1%). Fixed at deployment, cannot be changed.
    uint16 public immutable feeBps;

    /// @notice Where the fee goes. Fixed at deployment.
    address public immutable feeRecipient;

    /// @notice Share of freshly minted LP that gets permanently burned to
    ///         0x...dead on every launch, in basis points. 10_000 = 100% of
    ///         LP locked forever (full rug-proofing). Fixed at deployment.
    uint16 public immutable lpBurnBps;

    /// @notice Human-readable label for this launcher instance (shown by
    ///         indexers/frontends), e.g. "Hoodie Jake's Launcher".
    string public launcherName;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint16 public constant BPS_DENOMINATOR = 10_000;

    struct Launch {
        address token;
        address pair;
        address creator;
        uint256 totalSupply;
        uint256 hoodieSeeded;
        uint256 lpBurned;
        uint256 timestamp;
    }

    Launch[] public launches;

    event TokenLaunched(
        uint256 indexed launchIndex,
        address indexed token,
        address indexed pair,
        address creator,
        uint256 totalSupply,
        uint256 hoodieSeeded,
        uint256 feeTaken,
        uint256 lpBurned
    );

    error ZeroAmount();
    error FeeTooHigh();
    error LpBurnTooHigh();

    constructor(address hoodie_, uint16 feeBps_, address feeRecipient_, uint16 lpBurnBps_, string memory launcherName_) {
        if (feeBps_ > 1000) revert FeeTooHigh(); // hard cap: no launcher can ever take more than 10%
        if (lpBurnBps_ > BPS_DENOMINATOR) revert LpBurnTooHigh();
        hoodie = IERC20(hoodie_);
        feeBps = feeBps_;
        feeRecipient = feeRecipient_;
        lpBurnBps = lpBurnBps_;
        launcherName = launcherName_;
    }

    function launchesCount() external view returns (uint256) {
        return launches.length;
    }

    /// @notice Create a new token and seed it into a fresh $HOODIE pool.
    /// @param name Token name.
    /// @param symbol Token symbol.
    /// @param totalSupply Fixed total supply, minted entirely to this
    ///        contract then deposited into the pool — nothing held back.
    /// @param hoodieSeedAmount Amount of $HOODIE the caller is contributing
    ///        as the other side of the pool. Caller must have called
    ///        hoodie.approve(address(this), hoodieSeedAmount) beforehand.
    /// @return token The new token's address.
    /// @return pair The new HoodiePair's address.
    function launchToken(string calldata name, string calldata symbol, uint256 totalSupply, uint256 hoodieSeedAmount)
        external
        nonReentrant
        returns (address token, address pair)
    {
        if (totalSupply == 0 || hoodieSeedAmount == 0) revert ZeroAmount();

        LaunchedToken newToken = new LaunchedToken(name, symbol, totalSupply, address(this));
        HoodiePair newPair = new HoodiePair(
            address(hoodie), address(newToken), string.concat(name, "-HOODIE LP"), string.concat(symbol, "-HOODIE")
        );
        token = address(newToken);
        pair = address(newPair);

        hoodie.safeTransferFrom(msg.sender, address(this), hoodieSeedAmount);

        uint256 fee = (hoodieSeedAmount * feeBps) / BPS_DENOMINATOR;
        uint256 hoodieToPool = hoodieSeedAmount - fee;
        if (fee > 0) hoodie.safeTransfer(feeRecipient, fee);

        hoodie.safeTransfer(pair, hoodieToPool);
        newToken.transfer(pair, totalSupply);

        uint256 liquidity = newPair.mint(address(this));

        uint256 lpToBurn = (liquidity * lpBurnBps) / BPS_DENOMINATOR;
        if (lpToBurn > 0) newPair.transfer(BURN_ADDRESS, lpToBurn);
        uint256 lpToCreator = liquidity - lpToBurn;
        if (lpToCreator > 0) newPair.transfer(msg.sender, lpToCreator);

        launches.push(
            Launch({
                token: token,
                pair: pair,
                creator: msg.sender,
                totalSupply: totalSupply,
                hoodieSeeded: hoodieToPool,
                lpBurned: lpToBurn,
                timestamp: block.timestamp
            })
        );

        emit TokenLaunched(launches.length - 1, token, pair, msg.sender, totalSupply, hoodieToPool, fee, lpToBurn);
    }
}
