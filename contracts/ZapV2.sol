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
        require(owner() != address(0), "ZapV2ETH: owner must be set");

        ROUTER = IJoeRouter02(_router);
    }

    receive() external payable {}

    /* ========== View Functions ========== */

    //    function getAmountOutMin(
    //        address pairAddress,
    //        address tokenIn,
    //        uint256 amountIn,
    //        uint256 slippage
    //    )  public view returns (uint256) {
    //        require(slippage <= 490, "ZapV2: slippage too high");
    //        IJoePair pair = IJoePair(pairAddress);
    //        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
    //        uint256 ratio = tokenIn == pair.token0() ? reserve1.mul(1e18).div(reserve0) : reserve0.mul(1e18).div(reserve1);
    //
    //        return ratio.mul(1000 - slippage).mul(amountIn).div(1000).div(1e18);
    //    }

    /* ========== External Functions ========== */

    function zapInToken(
        address tokenFrom,
        uint256 amountFrom,
        uint256 amount0Min,
        uint256 amount1Min,
        address[] calldata pathToToken0,
        address[] calldata pathToToken1
    ) public {
        IERC20(tokenFrom).safeTransferFrom(msg.sender, address(this), amountFrom);
        _approveTokenIfNeeded(tokenFrom, amountFrom);

        (address token0, address token1) = _getTokens(pathToToken0, pathToToken1);

        uint256 amount0 = _swapHalfIfNeeded(amountFrom, amount0Min, pathToToken0);
        uint256 amount1 = _swapHalfIfNeeded(amountFrom, amount1Min, pathToToken1);

        _approveTokenIfNeeded(token0, amount0);
        _approveTokenIfNeeded(token1, amount1);

        ROUTER.addLiquidity(
        token0,
        token1,
        amount0,
        amount1,
        amount0Min,
        amount1Min,
        msg.sender,
        block.timestamp
        );
    }

    function zapIn(
        uint256 amount0Min,
        uint256 amount1Min,
        address[] calldata pathToToken0,
        address[] calldata pathToToken1
    ) external payable {
        IWAVAX(WAVAX).deposit{value: msg.value}();
        zapInToken(
            WAVAX,
            msg.value,
            amount0Min,
            amount1Min,
            pathToToken0,
            pathToToken1
        );
    }

    function zapOut(
        address pairFrom,
        uint256 amountFrom,
        uint256 amountToMin,
        address[] calldata pathFromToken0,
        address[] calldata pathFromToken1
    ) external {
        IERC20(pairFrom).safeTransferFrom(msg.sender, address(this), amountFrom);
        _approveTokenIfNeeded(pairFrom, amountFrom);

        IJoePair pair = IJoePair(pairFrom);
        address token0 = pair.token0();
        address token1 = pair.token1();

        (uint256 balance0, uint256 balance1) = _removeLiquidity(token0, token1, amountFrom);

        uint256 balance = _swapExactTokensForTokens(balance0, 0, pathFromToken0);
        balance += _swapExactTokensForTokens(balance1, 0, pathFromToken1);

        require(balance >= amountToMin, "ZapV2: INSUFFICIENT_TOKEN_AMOUNT");
    }

    /* ========== Private Functions ========== */

    function _approveTokenIfNeeded(address token, uint256 amount) private {
        if (IERC20(token).allowance(address(this), address(ROUTER)) < amount) {
            IERC20(token).safeApprove(address(ROUTER), uint256(~0));
        }
    }

    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) private returns (uint256 balanceOut){
        IERC20 tokenOut = IERC20(path[path.length - 1]);
        uint256 balanceBefore = tokenOut.balanceOf(address(this));
        ROUTER.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp);
        balanceOut = tokenOut.balanceOf(address(this)).sub(balanceBefore);
        require(balanceOut >= amountOutMin, "ZapV2: INSUFFICIENT_TOKEN_AMOUNT");
    }

    function _swapHalfIfNeeded(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) private returns (uint256 amountOut){
        uint256 sellAmount = amountIn / 2;
        if (path.length >= 2)
            amountOut = _swapExactTokensForTokens(amountIn.div(2), amountOutMin, path);
        else
            amountOut = sellAmount;
    }

    function _getTokens(
        address[] calldata path0,
        address[] calldata path1
    ) private pure returns (address, address){
        uint256 len0 = path0.length;
        uint256 len1 = path1.length;
        return (path0[len0 - 1], path1[len1 - 1]);
    }

    function _removeLiquidity(
        address token0Address,
        address token1Address,
        uint256 amount
    ) private returns (uint256 balance0, uint256 balance1) {
        IERC20 token0 = IERC20(token0Address);
        IERC20 token1 = IERC20(token1Address);

        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        ROUTER.removeLiquidity(
            token0Address,
            token1Address,
            amount,
            0,
            0,
            address(this),
            block.timestamp
        );
        balance0 = token0.balanceOf(address(this)) - balance0Before;
        balance1 = token0.balanceOf(address(this)) - balance1Before;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function withdraw(address token) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }

        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}
