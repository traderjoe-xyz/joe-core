// SPDX-License-Identifier: MIT

// P1 - P3: OK
pragma solidity 0.6.12;

import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";

import "./traderjoe/interfaces/IERC20.sol";
import "./traderjoe/interfaces/IJoePair.sol";
import "./traderjoe/interfaces/IJoeFactory.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

// JoeMakerV4 is MasterJoe's left hand and kinda a wizard. He can cook up any token from pretty much anything!
// This contract handles "serving up" rewards for xJoe holders by trading tokens collected from fees.

// T1 - T4: OK
contract JoeMakerV4 is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IJoeFactory public immutable factory;

    address public immutable bar;
    address private immutable wavax;
    address public tokenTo; //any erc20
    uint256 public devCut = 0; // in basis points aka parts per 10,000 so 5000 is 50%, cap of 50%, default is 0
    address public devAddr;

    // set of addresses that can perform certain functions
    mapping(address => bool) public isAuth;
    address[] public authorized;
    bool public anyAuth = false;

    modifier onlyAuth() {
        require(isAuth[msg.sender] || anyAuth, "JoeMakerV4: FORBIDDEN");
        _;
    }

    // V1 - V5: OK
    mapping(address => address) internal _bridges;

    event SetDevAddr(address _addr);
    event SetDevCut(uint256 _amount);
    event SetTokenTo(address _tokenTo);
    event LogBridgeSet(address indexed token, address indexed bridge);
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountTOKEN
    );

    constructor(
        address _factory,
        address _bar,
        address _tokenTo,
        address _wavax
    ) public {
        factory = IJoeFactory(_factory);
        bar = _bar;
        tokenTo = _tokenTo;
        wavax = _wavax;
        devAddr = msg.sender;
        isAuth[msg.sender] = true;
        authorized.push(msg.sender);
    }

    // Begin Owner functions
    function addAuth(address _auth) external onlyOwner {
        isAuth[_auth] = true;
        authorized.push(_auth);
    }

    function revokeAuth(address _auth) external onlyOwner {
        isAuth[_auth] = false;
    }

    // setting anyAuth to true allows anyone to call functions protected by onlyAuth
    function setAnyAuth(bool access) external onlyOwner {
        anyAuth = access;
    }

    function setBridge(address token, address bridge) external onlyOwner {
        // Checks
        require(token != tokenTo && token != wavax && token != bridge, "JoeMakerV4: Invalid bridge");

        // Effects
        _bridges[token] = bridge;
        emit LogBridgeSet(token, bridge);
    }

    function setDevCut(uint256 _amount) external onlyOwner {
        require(_amount <= 5000, "setDevCut: cut too high");
        devCut = _amount;

        emit SetDevCut(_amount);
    }

    function setDevAddr(address _addr) external onlyOwner {
        require(_addr != address(0), "setDevAddr, address cannot be zero address");
        devAddr = _addr;

        emit SetDevAddr(_addr);
    }

    function setTokenToAddress(address _tokenTo) external onlyOwner {
        require(_tokenTo != address(0), "setTokenToAddress, address cannot be zero address");
        tokenTo = _tokenTo;

        emit SetTokenTo(_tokenTo);
    }

    // End owner functions

    function bridgeFor(address token) public view returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = wavax;
        }
    }

    // C6: It's not a fool proof solution, but it prevents flash loans, so here it's ok to use tx.origin
    modifier onlyEOA() {
        // Try to make flash-loan exploit harder to do by only allowing externally owned addresses.
        require(msg.sender == tx.origin, "JoeMakerV4: must use EOA");
        _;
    }

    // F1 - F10: OK
    // F3: _convert is separate to save gas by only checking the 'onlyEOA' modifier once in case of convertMultiple
    // F6: There is an exploit to add lots of TOKEN to the bar, run convert, then remove the TOKEN again.
    //     As the size of the JoeBar has grown, this requires large amounts of funds and isn't super profitable anymore
    //     The onlyEOA modifier prevents this being done with a flash loan.
    // C1 - C24: OK
    function convert(
        address token0,
        address token1,
        uint256 slippage
    ) external onlyEOA onlyAuth {
        require(slippage < 5_000, "JoeMakerV4: slippage needs to be lower than 5000");
        _convert(token0, token1, slippage);
    }

    // F1 - F10: OK, see convert
    // C1 - C24: OK
    // C3: Loop is under control of the caller
    function convertMultiple(
        address[] calldata token0,
        address[] calldata token1,
        uint256 slippage
    ) external onlyEOA onlyAuth {
        // TODO: This can be optimized a fair bit, but this is safer and simpler for now
        require(slippage < 5_000, "JoeMakerV4: slippage needs to be lower than 5000");

        uint256 len = token0.length;
        for (uint256 i = 0; i < len; i++) {
            _convert(token0[i], token1[i], slippage);
        }
    }

    // F1 - F10: OK
    // C1- C24: OK
    function _convert(
        address token0,
        address token1,
        uint256 slippage
    ) internal {
        uint256 amount0;
        uint256 amount1;

        // handle case where non-LP tokens need to be converted
        if (token0 == token1) {
            amount0 = IERC20(token0).balanceOf(address(this));
            amount1 = 0;
        } else {
            IJoePair pair = IJoePair(factory.getPair(token0, token1));
            require(address(pair) != address(0), "JoeMakerV4: Invalid pair");

            IERC20(address(pair)).safeTransfer(address(pair), pair.balanceOf(address(this)));

            // take balance of tokens in this contract before burning the pair, incase there are already some here
            uint256 tok0bal = IERC20(token0).balanceOf(address(this));
            uint256 tok1bal = IERC20(token1).balanceOf(address(this));

            pair.burn(address(this));

            // subtract old balance of tokens from new balance
            // the return values of pair.burn cant be trusted due to transfer tax tokens
            amount0 = IERC20(token0).balanceOf(address(this)).sub(tok0bal);
            amount1 = IERC20(token1).balanceOf(address(this)).sub(tok1bal);
        }
        emit LogConvert(
            msg.sender,
            token0,
            token1,
            amount0,
            amount1,
            _convertStep(token0, token1, amount0, amount1, slippage)
        );
    }

    // F1 - F10: OK
    // C1 - C24: OK
    // All safeTransfer, _swap, _toTOKEN, _convertStep: X1 - X5: OK
    function _convertStep(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 slippage
    ) internal returns (uint256 tokenOut) {
        // Interactions
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == tokenTo) {
                IERC20(tokenTo).safeTransfer(bar, amount);
                tokenOut = amount;
            } else if (token0 == wavax) {
                tokenOut = _toToken(wavax, amount, slippage);
            } else {
                address bridge = bridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this), slippage);
                tokenOut = _convertStep(bridge, bridge, amount, 0, slippage);
            }
        } else if (token0 == tokenTo) {
            // eg. TOKEN - AVAX
            IERC20(tokenTo).safeTransfer(bar, amount0);
            tokenOut = _toToken(token1, amount1, slippage).add(amount0);
        } else if (token1 == tokenTo) {
            // eg. USDT - TOKEN
            IERC20(tokenTo).safeTransfer(bar, amount1);
            tokenOut = _toToken(token0, amount0, slippage).add(amount1);
        } else if (token0 == wavax) {
            // eg. AVAX - USDC
            tokenOut = _toToken(wavax, _swap(token1, wavax, amount1, address(this), slippage).add(amount0), slippage);
        } else if (token1 == wavax) {
            // eg. USDT - AVAX
            tokenOut = _toToken(wavax, _swap(token0, wavax, amount0, address(this), slippage).add(amount1), slippage);
        } else {
            // eg. MIC - USDT
            address bridge0 = bridgeFor(token0);
            address bridge1 = bridgeFor(token1);
            if (bridge0 == token1) {
                // eg. MIC - USDT - and bridgeFor(MIC) = USDT
                tokenOut = _convertStep(
                    bridge0,
                    token1,
                    _swap(token0, bridge0, amount0, address(this), slippage),
                    amount1,
                    slippage
                );
            } else if (bridge1 == token0) {
                // eg. WBTC - DSD - and bridgeFor(DSD) = WBTC
                tokenOut = _convertStep(
                    token0,
                    bridge1,
                    amount0,
                    _swap(token1, bridge1, amount1, address(this), slippage),
                    slippage
                );
            } else {
                tokenOut = _convertStep(
                    bridge0,
                    bridge1, // eg. USDT - DSD - and bridgeFor(DSD) = WBTC
                    _swap(token0, bridge0, amount0, address(this), slippage),
                    _swap(token1, bridge1, amount1, address(this), slippage),
                    slippage
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
        address to,
        uint256 slippage
    ) internal returns (uint256 amountOut) {
        // Checks
        // X1 - X5: OK
        IJoePair pair = IJoePair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "JoeMakerV4: Cannot convert");

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        (uint256 reserveInput, uint256 reserveOutput) = fromToken == pair.token0()
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        IERC20(fromToken).safeTransfer(address(pair), amountIn);
        uint256 amountInput = IERC20(fromToken).balanceOf(address(pair)).sub(reserveInput); // calculate amount that was transferred, this accounts for transfer taxes

        amountOut = getAmountOut(amountInput, reserveInput, reserveOutput);

        {
            uint256 rest = uint256(10_000).sub(slippage);
            require(
                getAmountOut(amountOut, reserveOutput, reserveInput) > amountInput.mul(rest).mul(rest).div(100_000_000),
                "JoeMakerV4: Slippage caught"
            );
        }
        (uint256 amount0Out, uint256 amount1Out) = fromToken == pair.token0()
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));
        pair.swap(amount0Out, amount1Out, to, new bytes(0));
    }

    // F1 - F10: OK
    // C1 - C24: OK
    function _toToken(
        address token,
        uint256 amountIn,
        uint256 slippage
    ) internal returns (uint256 amountOut) {
        uint256 amount = amountIn;
        if (devCut > 0) {
            amount = amount.mul(devCut).div(10000);
            IERC20(token).safeTransfer(devAddr, amount);
            amount = amountIn.sub(amount);
        }
        amountOut = _swap(token, tokenTo, amount, bar, slippage);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "JoeMakerV4: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "JoeMakerV4: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
}
