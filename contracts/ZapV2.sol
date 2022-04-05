// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "./traderjoe/interfaces/IJoeFactory.sol";
import "./traderjoe/interfaces/IJoePair.sol";
import "./traderjoe/interfaces/IJoeRouter02.sol";
import "./traderjoe/interfaces/IWAVAX.sol";

/// @title ZapV2
/// @author Trader Joe
/// @notice Allows to zapIn from an ERC20 or AVAX to a JoePair and
/// zapTo from a JoePair to an ERC20 or AVAX
/// @dev Dusts from zap can be withdrawn by owner
contract ZapV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== VARIABLES ========== */

    IWAVAX public immutable wavax;

    IJoeRouter02 public immutable router;

    IJoeFactory public immutable factory;

    /* ========== EVENTS ========== */

    event ZapInToken(
        address indexed sender,
        IERC20Upgradeable indexed tokenFrom,
        uint256 amountFrom,
        address indexed pairTo,
        uint256 amountTo
    );

    event ZapInAvax(address indexed sender, uint256 amountAvax, address indexed pairTo, uint256 amountTo);

    event ZapOutToken(
        address indexed sender,
        IJoePair indexed pairFrom,
        uint256 amountFrom,
        address tokenTo,
        uint256 amountTo
    );

    event ZapOutAvax(address indexed sender, IJoePair indexed pairFrom, uint256 amountFrom, uint256 amountAvax);

    /* ========== INITIALIZER ========== */

    /// @notice Constructor
    /// @param _wavax The address of wavax
    /// @param _router The address of router
    constructor(IWAVAX _wavax, IJoeRouter02 _router) public {
        __Ownable_init();
        __ReentrancyGuard_init();
        require(_wavax != IWAVAX(0), "ZapV2: wavax can't be address 0");
        require(_router != IJoeRouter02(0), "ZapV2: router can't be address 0");

        wavax = _wavax;
        router = _router;
        factory = IJoeFactory(_router.factory());
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /// @notice TokenFrom is the first value of `pathToPairToken(0/1)` array.
    /// Swaps half of it to token0 and the other half token1 and add liquidity
    /// with the swapped amounts
    /// @dev Any excess from adding liquidity is kept by ZapV2
    /// @param amountFrom The amountFrom of tokenFrom to zap
    /// @param amount0Min The min amount to receive of token0
    /// @param amount1Min The min amount to receive of token1
    /// @param pathToPairToken0 The path to the pair's token0
    /// @param pathToPairToken1 The path to the pair's token1
    function zapInToken(
        uint256 amountFrom,
        uint256 amount0Min,
        uint256 amount1Min,
        address[] calldata pathToPairToken0,
        address[] calldata pathToPairToken1
    ) external nonReentrant {
        require(amountFrom > 0, "ZapV2: Insufficient amount");
        address pair = factory.getPair(
            pathToPairToken0[pathToPairToken0.length - 1],
            pathToPairToken1[pathToPairToken1.length - 1]
        ); // Not necessary, but improves contract clarity
        require(pair != address(0), "ZapV2: Invalid target path");

        IERC20Upgradeable token = IERC20Upgradeable(pathToPairToken0[0]);

        // Transfer tax tokens safeguard
        uint256 previousBalance = token.balanceOf(address(this));
        token.safeTransferFrom(_msgSender(), address(this), amountFrom);
        uint256 amountReceived = token.balanceOf(address(this)).sub(previousBalance);

        uint256 amountTo = _zapInToken(
            token,
            amountReceived,
            amount0Min,
            amount1Min,
            pathToPairToken0,
            pathToPairToken1
        );

        emit ZapInToken(_msgSender(), token, amountFrom, pair, amountTo);
    }

    /// @notice Swaps half of AVAX to token0 and the other half token1 and
    /// add liquidity with the swapped amounts
    /// @dev Any excess from adding liquidity is kept by ZapV2
    /// @param amount0Min The min amount of token0 to add liquidity
    /// @param amount1Min The min amount to token1 to add liquidity
    /// @param pathToPairToken0 The path to the pair's token0
    /// @param pathToPairToken1 The path to the pair's token1
    function zapInAVAX(
        uint256 amount0Min,
        uint256 amount1Min,
        address[] calldata pathToPairToken0,
        address[] calldata pathToPairToken1
    ) external payable nonReentrant {
        require(msg.value > 0, "ZapV2: Insufficient amount");
        require(pathToPairToken0[0] == address(wavax), "ZapV2: Path needs to start with wavax");
        address pair = factory.getPair(
            pathToPairToken0[pathToPairToken0.length - 1],
            pathToPairToken1[pathToPairToken1.length - 1]
        ); // Not necessary, but improves contract clarity
        require(pair != address(0), "ZapV2: Invalid target path");

        wavax.deposit{value: msg.value}();

        uint256 liquidity = _zapInToken(
            IERC20Upgradeable(address(wavax)),
            msg.value,
            amount0Min,
            amount1Min,
            pathToPairToken0,
            pathToPairToken1
        );

        emit ZapInAvax(_msgSender(), msg.value, pair, liquidity);
    }

    /// @notice Unwrap Pair and swap the 2 tokens to path(0/1)[-1]
    /// @dev path0 and path1 do not need to be ordered
    /// @param amountFrom The amount of liquidity to zap
    /// @param amountToMin The min amount to receive of tokenTo
    /// @param path0 The path to one of the pair's token
    /// @param path1 The path to one of the pair's token
    function zapOutToken(
        uint256 amountFrom,
        uint256 amountToMin,
        address[] calldata path0,
        address[] calldata path1
    ) external nonReentrant {
        IJoePair pairFrom = IJoePair(factory.getPair(path0[0], path1[0]));
        require(pairFrom != IJoePair(0), "ZapV2: Invalid start path");

        uint256 amount = _zapOutToken(pairFrom, amountFrom, amountToMin, path0, path1, _msgSender());

        emit ZapOutToken(_msgSender(), pairFrom, amountFrom, path0[0], amount);
    }

    /// @notice Unwrap Pair and swap the 2 tokens to path(0/1)[-1]
    /// @dev path0 and path1 do not need to be ordered
    /// @param amountFrom The amount of liquidity to zap
    /// @param amountToMin The min amount to receive of token1
    /// @param path0 The path to one of the pair's token
    /// @param path1 The path to one of the pair's token
    function zapOutAVAX(
        uint256 amountFrom,
        uint256 amountToMin,
        address[] calldata path0,
        address[] calldata path1
    ) external nonReentrant {
        require(path0[path0.length - 1] == address(wavax), "ZapV2: Path needs to end with wavax");
        IJoePair pairFrom = IJoePair(factory.getPair(path0[0], path1[0]));
        require(pairFrom != IJoePair(0), "ZapV2: Invalid start path");

        uint256 amountAvax = _zapOutToken(pairFrom, amountFrom, amountToMin, path0, path1, address(this));

        wavax.withdraw(amountAvax);
        safeTransferAvax(_msgSender(), amountAvax);

        emit ZapOutAvax(_msgSender(), pairFrom, amountFrom, amountAvax);
    }

    /// @notice Allows the contract to receive AVAX
    /// @dev It is necessary to be able to receive AVAX when using wavax.withdraw()
    receive() external payable {}

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice Withdraw token to owner of the ZapV2 contract
    /// @dev if token's address is null address, sends AVAX
    /// @param token The token to withdraw
    function withdraw(IERC20Upgradeable token) external onlyOwner {
        if (token == IERC20Upgradeable(0)) {
            safeTransferAvax(_msgSender(), address(this).balance);
        } else {
            token.transfer(_msgSender(), token.balanceOf(address(this)));
        }
    }

    /* ========== Private Functions ========== */

    /// @notice Swaps half of tokenFrom to token0 and the other half token1 and add liquidity
    /// with the swapped amounts
    /// @dev Any excess from adding liquidity is kept by ZapV2
    /// @param token The token to zap from
    /// @param amountFrom The amountFrom of tokenFrom to zap
    /// @param amount0Min The min amount to receive of token0
    /// @param amount1Min The min amount to receive of token1
    /// @param pathToPairToken0 The path to the pair's token0
    /// @param pathToPairToken1 The path to the pair's token
    /// @return liquidity The amount of liquidity received
    function _zapInToken(
        IERC20Upgradeable token,
        uint256 amountFrom,
        uint256 amount0Min,
        uint256 amount1Min,
        address[] calldata pathToPairToken0,
        address[] calldata pathToPairToken1
    ) private returns (uint256 liquidity) {
        require(pathToPairToken0[0] == pathToPairToken1[0], "ZapV2: Invalid start path");
        _approveTokenIfNeeded(token, amountFrom);

        uint256 sellAmount = amountFrom / 2;
        uint256 amount0 = _swapExactTokensForTokens(sellAmount, 0, pathToPairToken0, address(this));
        uint256 amount1 = _swapExactTokensForTokens(amountFrom - sellAmount, 0, pathToPairToken1, address(this));

        require(amount0 >= amount0Min && amount1 >= amount1Min, "ZapV2: insufficient swapped amounts");

        liquidity = _addLiquidity(amount0, amount1, amount0Min, amount1Min, pathToPairToken0, pathToPairToken1);
    }

    /// @notice Unwrap Pair and swap the 2 tokens to path(0/1)[-1]
    /// @dev path0 and path1 do not need to be ordered
    /// @param pair The pair to unwrap
    /// @param amountFrom The amount of liquidity to zap
    /// @param amountToMin The min amount to receive of token1
    /// @param path0 The path to one of the pair's token
    /// @param path1 The path to one of the pair's token
    /// @param to The address to send the token
    /// @return amountTo The amount of tokenTo received
    function _zapOutToken(
        IJoePair pair,
        uint256 amountFrom,
        uint256 amountToMin,
        address[] calldata path0,
        address[] calldata path1,
        address to
    ) private returns (uint256 amountTo) {
        require(amountFrom > 0, "ZapV2: Insufficient amount");
        require(path0[path0.length - 1] == path1[path1.length - 1], "ZapV2: invalid end path");
        pair.transferFrom(_msgSender(), address(this), amountFrom);

        (uint256 balance0, uint256 balance1) = _removeLiquidity(pair, amountFrom);

        if (path0[0] > path1[0]) {
            (path0, path1) = (path1, path0);
        }

        amountTo = _swapExactTokensForTokens(balance0, 0, path0, to);
        amountTo = amountTo.add(_swapExactTokensForTokens(balance1, 0, path1, to));

        require(amountTo >= amountToMin, "ZapV2: insufficient swapped amounts");
    }

    /// @notice Approves the token if needed
    /// @param token The address of the token
    /// @param amount The amount of token to send
    function _approveTokenIfNeeded(IERC20Upgradeable token, uint256 amount) private {
        if (token.allowance(address(this), address(router)) < amount) {
            token.safeApprove(address(router), ~uint256(0));
        }
    }

    /// @notice Swaps exact tokenFrom following path
    /// @param amountFrom The amount of tokenFrom to swap
    /// @param amountToMin The min amount of tokenTo to receive
    /// @param path The path to follow to swap tokenFrom to TokenTo
    /// @param to The address that will receive tokenTo
    /// @return amountTo The amount of token received
    function _swapExactTokensForTokens(
        uint256 amountFrom,
        uint256 amountToMin,
        address[] calldata path,
        address to
    ) private returns (uint256 amountTo) {
        uint256 len = path.length;
        IERC20Upgradeable token = IERC20Upgradeable(path[len - 1]);
        uint256 balanceBefore = token.balanceOf(to);

        if (len > 1) {
            _approveTokenIfNeeded(IERC20Upgradeable(path[0]), amountFrom);
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountFrom,
                amountToMin,
                path,
                to,
                block.timestamp
            );
            amountTo = token.balanceOf(to) - balanceBefore;
        } else {
            if (to != address(this)) {
                token.safeTransfer(to, amountFrom);
                amountTo = token.balanceOf(to) - balanceBefore;
            } else {
                amountTo = amountFrom;
            }
        }
        require(amountTo >= amountToMin, "ZapV2: insufficient token amount");
    }

    /// @notice Adds liquidity to the pair of the last 2 tokens of paths
    /// @param amount0 The amount of token0 to add to liquidity
    /// @param amount1 The amount of token1 to add to liquidity
    /// @param amount0Min The min amount of token0 to add to liquidity
    /// @param amount1Min The min amount of token0 to add to liquidity
    /// @param pathToPairToken0 The path from tokenFrom to one of the pair's tokens
    /// @param pathToPairToken1 The path from tokenFrom to one of the pair's tokens
    /// @return liquidity The amount of liquidity added
    function _addLiquidity(
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Min,
        uint256 amount1Min,
        address[] calldata pathToPairToken0,
        address[] calldata pathToPairToken1
    ) private returns (uint256 liquidity) {
        (address token0, address token1) = (
            pathToPairToken0[pathToPairToken0.length - 1],
            pathToPairToken1[pathToPairToken1.length - 1]
        );

        _approveTokenIfNeeded(IERC20Upgradeable(token0), amount0);
        _approveTokenIfNeeded(IERC20Upgradeable(token1), amount1);

        (, , liquidity) = router.addLiquidity(
            token0,
            token1,
            amount0,
            amount1,
            amount0Min,
            amount1Min,
            _msgSender(),
            block.timestamp
        );
    }

    /// @notice Removes amount of liquidity from pair
    /// @param amount The amount of liquidity of the pair to unwrap
    /// @param pair The address of the pair
    /// @return token0Balance The actual amount of token0 received
    /// @return token1Balance The actual amount of token received
    function _removeLiquidity(IJoePair pair, uint256 amount) private returns (uint256, uint256) {
        _approveTokenIfNeeded(IERC20Upgradeable(address(pair)), amount);

        IERC20Upgradeable token0 = IERC20Upgradeable(pair.token0());
        IERC20Upgradeable token1 = IERC20Upgradeable(pair.token1());

        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        router.removeLiquidity(address(token0), address(token1), amount, 0, 0, address(this), block.timestamp);

        return (token0.balanceOf(address(this)) - balance0Before, token1.balanceOf(address(this)) - balance1Before);
    }

    /// @notice Transfer amount AVAX to address to
    /// @param to The address that will receives AVAX
    /// @param amount The amount of AVAX to transfer
    function safeTransferAvax(address to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        require(success, "ZapV2: avax transfer failed");
    }
}
