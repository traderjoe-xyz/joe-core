// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

/*
 * Trader Joe
 * MIT License; modified from PancakeBunny
 *
 */

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./traderjoe/interfaces/IJoePair.sol";
import "./traderjoe/interfaces/IJoeRouter02.sol";
import "./traderjoe/interfaces/IWAVAX.sol";

contract ZapV2 is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== CONSTANT VARIABLES ========== */

    address public constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    IJoeRouter02 private ROUTER;

    /* ========== INITIALIZER ========== */

    constructor(address _router) public {
        require(owner() != address(0), "ZapV2: owner must be set");

        ROUTER = IJoeRouter02(_router);
    }

    receive() external payable {}

    /* ========== External Functions ========== */

    function zapInToken(
        address tokenFrom,
        uint256 amountFrom,
        uint256 amount0Min,
        uint256 amount1Min,
        address[] calldata pathToToken0,
        address[] calldata pathToToken1
    ) external {
        IERC20 token = IERC20(tokenFrom);
        uint256 balanceBefore = token.balanceOf(address(this));
        IERC20(tokenFrom).safeTransferFrom(msg.sender, address(this), amountFrom);
        uint256 amount = token.balanceOf(address(this)) - balanceBefore;

        _zapInToken(tokenFrom, amount, amount0Min, amount1Min, pathToToken0, pathToToken1, msg.sender);
    }

    function zapInAVAX(
        uint256 amount0Min,
        uint256 amount1Min,
        address[] calldata pathToToken0,
        address[] calldata pathToToken1
    ) external payable {
        IWAVAX(WAVAX).deposit{value: msg.value}();

        _zapInToken(WAVAX, msg.value, amount0Min, amount1Min, pathToToken0, pathToToken1, msg.sender);
    }

    function zapOutToken(
        address pairFrom,
        uint256 amountFrom,
        uint256 amountToMin,
        address[] calldata path0,
        address[] calldata path1
    ) external {
        _zapOutToken(pairFrom, amountFrom, amountToMin, path0, path1, msg.sender);
    }

    function zapOutAVAX(
        address pairFrom,
        uint256 amountFrom,
        uint256 amountToMin,
        address[] calldata path0,
        address[] calldata path1
    ) external {
        require(path0[path0.length - 1] == WAVAX, "ZapV2: INVALID_PATH"); /// path1 is check inside _zapOutToken.
        uint256 amountAvax = _zapOutToken(pairFrom, amountFrom, amountToMin, path0, path1, address(this));
        IWAVAX(WAVAX).withdraw(amountAvax);
        (bool sent, ) = msg.sender.call{value: amountAvax}("");
        require(sent, "ZapV2: AVAX transfer failed");
    }

    /* ========== Private Functions ========== */

    function _addLiquidity(
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Min,
        uint256 amount1Min,
        address[] calldata pathToToken0,
        address[] calldata pathToToken1,
        address to
    ) private returns (uint256 liquidity) {
        (address token0, address token1) = _getToTokens(pathToToken0, pathToToken1);

        _approveTokenIfNeeded(token0, amount0);
        _approveTokenIfNeeded(token1, amount1);

        (, , liquidity) = ROUTER.addLiquidity(
            token0,
            token1,
            amount0,
            amount1,
            amount0Min,
            amount1Min,
            to,
            block.timestamp
        );
    }

    function _approveTokenIfNeeded(address token, uint256 amount) private {
        if (IERC20(token).allowance(address(this), address(ROUTER)) < amount) {
            IERC20(token).safeApprove(address(ROUTER), uint256(~0));
        }
    }

    function _getToTokens(address[] calldata path0, address[] calldata path1) private pure returns (address, address) {
        uint256 len0 = path0.length;
        uint256 len1 = path1.length;
        return (path0[len0 - 1], path1[len1 - 1]);
    }

    function _orderPath(
        address pairFrom,
        address[] calldata path0,
        address[] calldata path1
    ) private view returns (address[] calldata pathFromToken0, address[] calldata pathFromToken1) {
        IJoePair pair = IJoePair(pairFrom);
        (pathFromToken0, pathFromToken1) = path0[0] == pair.token0() ? (path0, path1) : (path1, path0);
    }

    function _removeLiquidity(address pairFrom, uint256 amount) private returns (uint256 balance0, uint256 balance1) {
        IJoePair pair = IJoePair(pairFrom);
        address token0Address = pair.token0();
        address token1Address = pair.token1();

        IERC20 token0 = IERC20(token0Address);
        IERC20 token1 = IERC20(token1Address);

        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        ROUTER.removeLiquidity(token0Address, token1Address, amount, 0, 0, address(this), block.timestamp);
        balance0 = token0.balanceOf(address(this)) - balance0Before;
        balance1 = token1.balanceOf(address(this)) - balance1Before;

        _approveTokenIfNeeded(token0Address, balance0);
        _approveTokenIfNeeded(token1Address, balance1);
    }

    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) private returns (uint256 amountOut) {
        if (path.length >= 2) {
            IERC20 tokenOut = IERC20(path[path.length - 1]);
            uint256 balanceBefore = tokenOut.balanceOf(to);
            _approveTokenIfNeeded(path[0], amountIn);
            ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                block.timestamp
            );
            amountOut = tokenOut.balanceOf(to) - balanceBefore;
        } else {
            if (to != address(this)) {
                IERC20 token = IERC20(path[0]);
                uint256 balanceBefore = token.balanceOf(to);
                token.safeTransfer(to, amountIn);
                amountOut = token.balanceOf(to) - balanceBefore;
            } else {
                amountOut = amountIn;
            }
        }
        require(amountOut >= amountOutMin, "ZapV2: INSUFFICIENT_TOKEN_AMOUNT");
    }

    function _zapInToken(
        address tokenFrom,
        uint256 amountFrom,
        uint256 amount0Min,
        uint256 amount1Min,
        address[] calldata pathToToken0,
        address[] calldata pathToToken1,
        address to
    ) private returns (uint256 liquidity) {
        _approveTokenIfNeeded(tokenFrom, amountFrom);
        require(pathToToken0[0] == tokenFrom && pathToToken1[0] == tokenFrom, "ZapV2: INVALID_PATH");

        uint256 sellAmount = amountFrom / 2;
        uint256 amount0 = _swapExactTokensForTokens(sellAmount, 0, pathToToken0, address(this));
        uint256 amount1 = _swapExactTokensForTokens(amountFrom - sellAmount, 0, pathToToken1, address(this));

        require(amount0 >= amount0Min, "ZapV2: INSUFFICIENT_A_AMOUNT");
        require(amount1 >= amount1Min, "ZapV2: INSUFFICIENT_B_AMOUNT");

        liquidity = _addLiquidity(amount0, amount1, amount0Min, amount1Min, pathToToken0, pathToToken1, to);
    }

    function _zapOutToken(
        address pairFrom,
        uint256 amountFrom,
        uint256 amountToMin,
        address[] calldata path0,
        address[] calldata path1,
        address to
    ) private returns (uint256 balance) {
        IERC20(pairFrom).safeTransferFrom(msg.sender, address(this), amountFrom);
        _approveTokenIfNeeded(pairFrom, amountFrom);

        (address[] calldata pathFromToken0, address[] calldata pathFromToken1) = _orderPath(pairFrom, path0, path1);

        {
            (address token0, address token1) = _getToTokens(pathFromToken0, pathFromToken1);
            require(token0 == token1, "ZapV2: INVALID_PATH");
        }

        (uint256 balance0, uint256 balance1) = _removeLiquidity(pairFrom, amountFrom);

        balance = _swapExactTokensForTokens(balance0, 0, pathFromToken0, to);
        balance += _swapExactTokensForTokens(balance1, 0, pathFromToken1, to);

        require(balance >= amountToMin, "ZapV2: INSUFFICIENT_TOKEN_AMOUNT");
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function withdraw(address token) external onlyOwner {
        if (token == address(0)) {
            owner().call{value: address(this).balance}("");
            return;
        }

        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}
