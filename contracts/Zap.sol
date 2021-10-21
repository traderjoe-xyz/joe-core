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

import "./traderjoe/interfaces/IWAVAX.sol";
import "./traderjoe/interfaces/IJoePair.sol";
import "./traderjoe/interfaces/IJoeRouter02.sol";
import "./traderjoe/interfaces/IWAVAX.sol";
import "./traderjoe/interfaces/IJoeFactory.sol";

contract Zap is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== CONSTANT VARIABLES ========== */

    address public wavax;

    IJoeRouter02 private router;
    IJoeFactory private factory;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _wavax,
        address _router,
        address _factory
    ) public {
        wavax = _wavax;
        router = IJoeRouter02(_router);
        factory = IJoeFactory(_factory);
    }

    receive() external payable {}

    /* ========== External Functions ========== */

    function zapInToken(
        address token,
        uint256 amount,
        address pairAddress,
        uint256 minToken0Amount,
        uint256 minToken1Amount
    ) external {
        uint256 liquidity = _zapInToken(_msgSender(), token, amount, pairAddress, minToken0Amount, minToken1Amount);

        IERC20(pairAddress).safeTransfer(_msgSender(), liquidity);
    }

    function zapInAvax(
        address pairAddress,
        uint256 minToken0Amount,
        uint256 minToken1Amount
    ) external payable {
        uint256 avaxAmount = msg.value;
        IWAVAX(wavax).deposit{value: avaxAmount}();
        assert(IWAVAX(wavax).transfer(_msgSender(), avaxAmount));
        uint256 liquidity = _zapInToken(_msgSender(), wavax, avaxAmount, pairAddress, minToken0Amount, minToken1Amount);

        IERC20(pairAddress).safeTransfer(_msgSender(), liquidity);
    }

    function zapOutToken(
        address pairAddress,
        uint256 amount,
        address tokenOut,
        uint256 minAmount
    ) external {
        IERC20(pairAddress).safeTransferFrom(_msgSender(), address(this), amount);

        (address token0, address token1, uint256 amount0, uint256 amount1) = _removeLiquidity(pairAddress, amount);

        _approveTokenIfNeeded(token0);
        _approveTokenIfNeeded(token1);

        uint256 tokenAmount = _swapExactTokensToWavaxToToken(token0, token1, amount0, amount1, tokenOut, _msgSender());
        require(tokenAmount >= minAmount, "Zap: INSUFFICIENT_TOKEN_AMOUNT");
    }

    /* ========== Private Functions ========== */

    function _zapInToken(
        address from,
        address token,
        uint256 amountIn,
        address pairAddress,
        uint256 minToken0Amount,
        uint256 minToken1Amount
    ) private returns (uint256 liquidity) {
        uint256 token0Amount;
        uint256 token1Amount;

        uint256 amount = _transferFrom(from, address(this), token, amountIn);

        (address token0, address token1) = getTokensAndApprove(pairAddress);
        _approveTokenIfNeeded(wavax);

        if (token == token0 || token == token1) {
            if (token != token0) {
                (token0, token1) = (token1, token0);
            }

            token0Amount = amount.div(2);
            token1Amount = _swap(token0, token1, amount.sub(token0Amount), address(this));
        } else {
            (token0Amount, token1Amount) = _swapExactTokenToWavaxToTokens(token, amount, token0, token1);
        }

        (, , liquidity) = router.addLiquidity(
            token0,
            token1,
            token0Amount,
            token1Amount,
            minToken0Amount,
            minToken1Amount,
            address(this),
            block.timestamp
        );
    }

    function _transferFrom(
        address from,
        address to,
        address token,
        uint256 _amount
    ) private returns (uint256 amount) {
        IERC20 IERC20FromToken = IERC20(token);
        uint256 balanceBefore = IERC20FromToken.balanceOf(to);

        if (from == address(this)) {
            IERC20FromToken.safeTransfer(to, _amount);
        } else {
            IERC20FromToken.safeTransferFrom(from, to, _amount);
        }

        amount = IERC20FromToken.balanceOf(to).sub(balanceBefore);
    }

    function getTokensAndApprove(address pairAddress) private returns (address token0, address token1) {
        IJoePair pair = IJoePair(pairAddress);

        token0 = pair.token0();
        token1 = pair.token1();

        _approveTokenIfNeeded(token0);
        _approveTokenIfNeeded(token1);
    }

    function _removeLiquidity(address pairAddress, uint256 amount)
        private
        returns (
            address token0Address,
            address token1Address,
            uint256 amount0,
            uint256 amount1
        )
    {
        _approveTokenIfNeeded(pairAddress);

        IJoePair pair = IJoePair(pairAddress);

        token0Address = pair.token0();
        token1Address = pair.token1();

        IERC20 token0 = IERC20(token0Address);
        IERC20 token1 = IERC20(token1Address);

        uint256 balanceBefore0 = token0.balanceOf(address(this));
        uint256 balanceBefore1 = token1.balanceOf(address(this));

        router.removeLiquidity(token0Address, token1Address, amount, 0, 0, address(this), block.timestamp);

        amount0 = token0.balanceOf(address(this)).sub(balanceBefore0);
        amount1 = token1.balanceOf(address(this)).sub(balanceBefore1);
    }

    function _swapExactTokensToWavaxToToken(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        address tokenOut,
        address to
    ) private returns (uint256 tokenAmount) {
        _approveTokenIfNeeded(wavax);
        uint256 wavaxAmount;

        if (token0 != wavax) {
            _checkPairLiquidity(token0);
            wavaxAmount = _swap(token0, wavax, amount0, address(this));
        } else {
            wavaxAmount = amount0;
        }

        if (token1 != wavax) {
            _checkPairLiquidity(token1);
            wavaxAmount = wavaxAmount.add(_swap(token1, wavax, amount1, address(this)));
        } else {
            wavaxAmount = wavaxAmount.add(amount1);
        }

        if (tokenOut != wavax) {
            _checkPairLiquidity(tokenOut);
            tokenAmount = _swap(wavax, tokenOut, wavaxAmount, to);
        } else {
            IWAVAX(wavax).withdraw(wavaxAmount);

            (bool success, ) = to.call{value: wavaxAmount}("");
            require(success, "Transfer failed");
        }
    }

    function _swapExactTokenToWavaxToTokens(
        address fromToken,
        uint256 amount,
        address token0,
        address token1
    ) private returns (uint256 token0Amount, uint256 token1Amount) {
        uint256 wavaxAmount;

        if (fromToken != wavax) {
            _checkPairLiquidity(fromToken);
            wavaxAmount = _swap(fromToken, wavax, amount, address(this));
        } else {
            wavaxAmount = amount;
        }

        uint256 sellAmount = wavaxAmount.div(2);

        if (token0 != wavax) {
            _checkPairLiquidity(token0);
            token0Amount = _swap(wavax, token0, sellAmount, address(this));
        } else {
            token0Amount = sellAmount;
        }

        if (token1 != wavax) {
            _checkPairLiquidity(token1);
            token1Amount = _swap(wavax, token1, wavaxAmount.sub(sellAmount), address(this));
        } else {
            token1Amount = wavaxAmount.sub(sellAmount);
        }
    }

    function _approveTokenIfNeeded(address token) private {
        if (IERC20(token).allowance(address(this), address(router)) == 0) {
            IERC20(token).safeApprove(address(router), uint256(~0));
        }
    }

    function _checkPairLiquidity(address token) private view {
        IJoePair pair = IJoePair(factory.getPair(wavax, token));
        require(address(pair) != address(0), "Zap: Pair doesn't exist");

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        // Pair needs to have more than 50 000 avax in reserve.
        require((pair.token0() == wavax ? reserve0 : reserve1) > 50000e18, "Zap: Not enough liquidity");
    }

    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address to
    ) internal returns (uint256 amountOut) {
        IJoePair pair = IJoePair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "Zap: Pair doesn't exist");

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        uint256 balanceBefore = IERC20(toToken).balanceOf(to);

        uint256 amountInWithFee = _transferFrom(address(this), address(pair), fromToken, amountIn).mul(997);

        if (fromToken == pair.token0()) {
            amountOut = amountInWithFee.mul(reserve1).div(reserve0.mul(1000).add(amountInWithFee));
            pair.swap(0, amountOut, to, new bytes(0));
            // TODO: Add maximum slippage?
        } else {
            amountOut = amountInWithFee.mul(reserve0).div(reserve1.mul(1000).add(amountInWithFee));
            pair.swap(amountOut, 0, to, new bytes(0));
            // TODO: Add maximum slippage?
        }
        amountOut = IERC20(toToken).balanceOf(to).sub(balanceBefore);
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
