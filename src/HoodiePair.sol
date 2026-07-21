// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title HoodiePair
/// @notice A minimal, self-contained constant-product (x*y=k) AMM pool between
///         $HOODIE (token0) and one launched token (token1). This is the
///         mechanism that enforces the bounty's immutable rule: HOODIE is set
///         once in the constructor, is `immutable`, and there is no setter,
///         admin function, or upgrade path that could ever change it. Every
///         pool this contract represents is a HOODIE pool, permanently.
///
///         Deliberately not a Uniswap v2/v4 fork or integration. Robinhood
///         Chain's live Uniswap deployment is v4 with a modified Universal
///         Router (nonstandard calldata for stock-token hops per partner
///         docs), which is a real integration risk under a 3-day deadline.
///         This pool is small enough to read end to end and reason about
///         directly, and it doesn't depend on any address outside this repo
///         being correct.
///
///         LP shares are represented by this contract's own ERC20 balance
///         (mirrors the Uniswap v2 pattern). The first mint permanently locks
///         MINIMUM_LIQUIDITY to address(0) so the pool can't be fully drained
///         to zero and re-priced by the creator.
contract HoodiePair is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 private constant FEE_NUMERATOR = 997; // 0.3% swap fee, same shape as UniV2
    uint256 private constant FEE_DENOMINATOR = 1000;

    IERC20 public immutable hoodie; // token0 — always $HOODIE, never changes
    IERC20 public immutable token; // token1 — the token launched alongside it

    uint112 private reserveHoodie;
    uint112 private reserveToken;

    event Mint(address indexed sender, uint256 hoodieIn, uint256 tokenIn, uint256 liquidity);
    event Burn(address indexed sender, uint256 hoodieOut, uint256 tokenOut, address indexed to);
    event Swap(
        address indexed sender,
        uint256 hoodieIn,
        uint256 tokenIn,
        uint256 hoodieOut,
        uint256 tokenOut,
        address indexed to
    );
    event Sync(uint112 reserveHoodie, uint112 reserveToken);

    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error InsufficientLiquidity();
    error InvalidTo();
    error KInvariant();

    constructor(address hoodie_, address token_, string memory pairName, string memory pairSymbol)
        ERC20(pairName, pairSymbol)
    {
        hoodie = IERC20(hoodie_);
        token = IERC20(token_);
    }

    function getReserves() public view returns (uint112 _reserveHoodie, uint112 _reserveToken) {
        _reserveHoodie = reserveHoodie;
        _reserveToken = reserveToken;
    }

    /// @notice Mints LP tokens based on whatever hoodie/token balance has
    ///         already been transferred into this contract before calling.
    ///         Follows the standard "transfer then call" pattern so it can be
    ///         used both for the initial atomic seed from TokenLauncher and
    ///         for later top-ups by anyone.
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        (uint112 _reserveHoodie, uint112 _reserveToken) = getReserves();
        uint256 balanceHoodie = hoodie.balanceOf(address(this));
        uint256 balanceToken = token.balanceOf(address(this));
        uint256 amountHoodie = balanceHoodie - _reserveHoodie;
        uint256 amountToken = balanceToken - _reserveToken;

        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            liquidity = _sqrt(amountHoodie * amountToken) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY); // permanently locked, not just address(0)
        } else {
            liquidity = _min(
                (amountHoodie * totalSupply_) / _reserveHoodie, (amountToken * totalSupply_) / _reserveToken
            );
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(balanceHoodie, balanceToken);
        emit Mint(msg.sender, amountHoodie, amountToken, liquidity);
    }

    /// @notice Burns LP tokens held by this contract and returns the
    ///         underlying hoodie + token to `to`, pro-rata.
    function burn(address to) external nonReentrant returns (uint256 amountHoodie, uint256 amountToken) {
        uint256 balanceHoodie = hoodie.balanceOf(address(this));
        uint256 balanceToken = token.balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        uint256 totalSupply_ = totalSupply();
        amountHoodie = (liquidity * balanceHoodie) / totalSupply_;
        amountToken = (liquidity * balanceToken) / totalSupply_;
        if (amountHoodie == 0 || amountToken == 0) revert InsufficientLiquidityBurned();

        _burn(address(this), liquidity);
        hoodie.safeTransfer(to, amountHoodie);
        token.safeTransfer(to, amountToken);

        balanceHoodie = hoodie.balanceOf(address(this));
        balanceToken = token.balanceOf(address(this));
        _update(balanceHoodie, balanceToken);
        emit Burn(msg.sender, amountHoodie, amountToken, to);
    }

    /// @notice Standard constant-product swap. Caller must have already
    ///         transferred the input token to this contract (matches the
    ///         UniV2 low-level interface so routers/frontends can build
    ///         multicall bundles: transfer + swap in one user-signed tx via
    ///         a router, or two txs directly against the pair).
    function swap(uint256 amountHoodieOut, uint256 amountTokenOut, address to) external nonReentrant {
        if (amountHoodieOut == 0 && amountTokenOut == 0) revert InsufficientOutputAmount();
        (uint112 _reserveHoodie, uint112 _reserveToken) = getReserves();
        if (amountHoodieOut >= _reserveHoodie || amountTokenOut >= _reserveToken) revert InsufficientLiquidity();
        if (to == address(hoodie) || to == address(token)) revert InvalidTo();

        if (amountHoodieOut > 0) hoodie.safeTransfer(to, amountHoodieOut);
        if (amountTokenOut > 0) token.safeTransfer(to, amountTokenOut);

        uint256 balanceHoodie = hoodie.balanceOf(address(this));
        uint256 balanceToken = token.balanceOf(address(this));

        uint256 amountHoodieIn =
            balanceHoodie > _reserveHoodie - amountHoodieOut ? balanceHoodie - (_reserveHoodie - amountHoodieOut) : 0;
        uint256 amountTokenIn =
            balanceToken > _reserveToken - amountTokenOut ? balanceToken - (_reserveToken - amountTokenOut) : 0;
        if (amountHoodieIn == 0 && amountTokenIn == 0) revert InsufficientInputAmount();

        uint256 balanceHoodieAdjusted = (balanceHoodie * FEE_DENOMINATOR) - (amountHoodieIn * (FEE_DENOMINATOR - FEE_NUMERATOR));
        uint256 balanceTokenAdjusted = (balanceToken * FEE_DENOMINATOR) - (amountTokenIn * (FEE_DENOMINATOR - FEE_NUMERATOR));
        if (
            balanceHoodieAdjusted * balanceTokenAdjusted
                < uint256(_reserveHoodie) * uint256(_reserveToken) * (FEE_DENOMINATOR ** 2)
        ) revert KInvariant();

        _update(balanceHoodie, balanceToken);
        emit Swap(msg.sender, amountHoodieIn, amountTokenIn, amountHoodieOut, amountTokenOut, to);
    }

    /// @notice Pulls in any balance sitting above tracked reserves without
    ///         minting LP for it — a safety valve, not a normal-path function.
    function skim(address to) external nonReentrant {
        uint256 excessHoodie = hoodie.balanceOf(address(this)) - reserveHoodie;
        uint256 excessToken = token.balanceOf(address(this)) - reserveToken;
        if (excessHoodie > 0) hoodie.safeTransfer(to, excessHoodie);
        if (excessToken > 0) token.safeTransfer(to, excessToken);
    }

    function _update(uint256 balanceHoodie, uint256 balanceToken) private {
        reserveHoodie = uint112(balanceHoodie);
        reserveToken = uint112(balanceToken);
        emit Sync(reserveHoodie, reserveToken);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
