// SPDX-License-Identifier: MIT

// P1 - P3: OK
pragma solidity 0.6.12;
import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";

import "./traderjoe/interfaces/IJoeERC20.sol";
import "./traderjoe/interfaces/IJoePair.sol";
import "./traderjoe/interfaces/IJoeFactory.sol";

import "./boringcrypto/BoringOwnable.sol";

// JoeMaker is MasterJoe's left hand and kinda a wizard. He can cook up Joe from pretty much anything!
// This contract handles "serving up" rewards for xJoe holders by trading tokens collected from fees for Joe.

// T1 - T4: OK
contract JoeMaker is BoringOwnable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // V1 - V5: OK
    IJoeFactory public immutable factory;
    //0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac
    // V1 - V5: OK
    address public immutable bar;
    //0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272
    // V1 - V5: OK
    address private immutable joe;
    //0x6B3595068778DD592e39A122f4f5a5cF09C90fE2
    // V1 - V5: OK
    address private immutable wavax;
    //0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

    // V1 - V5: OK
    mapping(address => address) internal _bridges;

    // E1: OK
    event LogBridgeSet(address indexed token, address indexed bridge);
    // E1: OK
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountJOE
    );

    constructor(
        address _factory,
        address _bar,
        address _joe,
        address _wavax
    ) public {
        factory = IJoeFactory(_factory);
        bar = _bar;
        joe = _joe;
        wavax = _wavax;
    }

    // F1 - F10: OK
    // C1 - C24: OK
    function bridgeFor(address token) public view returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = wavax;
        }
    }

    // F1 - F10: OK
    // C1 - C24: OK
    function setBridge(address token, address bridge) external onlyOwner {
        // Checks
        require(token != joe && token != wavax && token != bridge, "JoeMaker: Invalid bridge");

        // Effects
        _bridges[token] = bridge;
        emit LogBridgeSet(token, bridge);
    }

    // M1 - M5: OK
    // C1 - C24: OK
    // C6: It's not a fool proof solution, but it prevents flash loans, so here it's ok to use tx.origin
    modifier onlyEOA() {
        // Try to make flash-loan exploit harder to do by only allowing externally owned addresses.
        require(msg.sender == tx.origin, "JoeMaker: must use EOA");
        _;
    }

    // F1 - F10: OK
    // F3: _convert is separate to save gas by only checking the 'onlyEOA' modifier once in case of convertMultiple
    // F6: There is an exploit to add lots of JOE to the bar, run convert, then remove the JOE again.
    //     As the size of the JoeBar has grown, this requires large amounts of funds and isn't super profitable anymore
    //     The onlyEOA modifier prevents this being done with a flash loan.
    // C1 - C24: OK
    function convert(address token0, address token1) external onlyEOA {
        _convert(token0, token1);
    }

    // F1 - F10: OK, see convert
    // C1 - C24: OK
    // C3: Loop is under control of the caller
    function convertMultiple(address[] calldata token0, address[] calldata token1) external onlyEOA {
        // TODO: This can be optimized a fair bit, but this is safer and simpler for now
        uint256 len = token0.length;
        for (uint256 i = 0; i < len; i++) {
            _convert(token0[i], token1[i]);
        }
    }

    // F1 - F10: OK
    // C1- C24: OK
    function _convert(address token0, address token1) internal {
        // Interactions
        // S1 - S4: OK
        IJoePair pair = IJoePair(factory.getPair(token0, token1));
        require(address(pair) != address(0), "JoeMaker: Invalid pair");
        // balanceOf: S1 - S4: OK
        // transfer: X1 - X5: OK
        IERC20(address(pair)).safeTransfer(address(pair), pair.balanceOf(address(this)));
        // X1 - X5: OK
        (uint256 amount0, uint256 amount1) = pair.burn(address(this));
        if (token0 != pair.token0()) {
            (amount0, amount1) = (amount1, amount0);
        }
        emit LogConvert(msg.sender, token0, token1, amount0, amount1, _convertStep(token0, token1, amount0, amount1));
    }

    // F1 - F10: OK
    // C1 - C24: OK
    // All safeTransfer, _swap, _toJOE, _convertStep: X1 - X5: OK
    function _convertStep(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 joeOut) {
        // Interactions
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == joe) {
                IERC20(joe).safeTransfer(bar, amount);
                joeOut = amount;
            } else if (token0 == wavax) {
                joeOut = _toJOE(wavax, amount);
            } else {
                address bridge = bridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this));
                joeOut = _convertStep(bridge, bridge, amount, 0);
            }
        } else if (token0 == joe) {
            // eg. JOE - AVAX
            IERC20(joe).safeTransfer(bar, amount0);
            joeOut = _toJOE(token1, amount1).add(amount0);
        } else if (token1 == joe) {
            // eg. USDT - JOE
            IERC20(joe).safeTransfer(bar, amount1);
            joeOut = _toJOE(token0, amount0).add(amount1);
        } else if (token0 == wavax) {
            // eg. AVAX - USDC
            joeOut = _toJOE(wavax, _swap(token1, wavax, amount1, address(this)).add(amount0));
        } else if (token1 == wavax) {
            // eg. USDT - AVAX
            joeOut = _toJOE(wavax, _swap(token0, wavax, amount0, address(this)).add(amount1));
        } else {
            // eg. MIC - USDT
            address bridge0 = bridgeFor(token0);
            address bridge1 = bridgeFor(token1);
            if (bridge0 == token1) {
                // eg. MIC - USDT - and bridgeFor(MIC) = USDT
                joeOut = _convertStep(bridge0, token1, _swap(token0, bridge0, amount0, address(this)), amount1);
            } else if (bridge1 == token0) {
                // eg. WBTC - DSD - and bridgeFor(DSD) = WBTC
                joeOut = _convertStep(token0, bridge1, amount0, _swap(token1, bridge1, amount1, address(this)));
            } else {
                joeOut = _convertStep(
                    bridge0,
                    bridge1, // eg. USDT - DSD - and bridgeFor(DSD) = WBTC
                    _swap(token0, bridge0, amount0, address(this)),
                    _swap(token1, bridge1, amount1, address(this))
                );
            }
        }
    }

    // F1 - F10: OK
    // C1 - C24: OK
    // All safeTransfer, swap: X1 - X5: OK
    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address to
    ) internal returns (uint256 amountOut) {
        // Checks
        // X1 - X5: OK
        IJoePair pair = IJoePair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "JoeMaker: Cannot convert");

        // Interactions
        // X1 - X5: OK
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        if (fromToken == pair.token0()) {
            amountOut = amountIn.mul(997).mul(reserve1) / reserve0.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(0, amountOut, to, new bytes(0));
            // TODO: Add maximum slippage?
        } else {
            amountOut = amountIn.mul(997).mul(reserve0) / reserve1.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(amountOut, 0, to, new bytes(0));
            // TODO: Add maximum slippage?
        }
    }

    // F1 - F10: OK
    // C1 - C24: OK
    function _toJOE(address token, uint256 amountIn) internal returns (uint256 amountOut) {
        // X1 - X5: OK
        amountOut = _swap(token, joe, amountIn, bar);
    }
}
