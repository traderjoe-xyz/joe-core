// SPDX-License-Identifier: MIT

// P1 - P3: OK
pragma solidity 0.6.12;

import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";

import "./traderjoe/interfaces/IERC20.sol";
import "./traderjoe/interfaces/IJoePair.sol";
import "./traderjoe/interfaces/IJoeFactory.sol";
import "./traderjoe/libraries/JoeLibrary.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

/// @title Money Maker
/// @author Trader Joe
/// @notice MoneyMaker receives 0.05% of the swaps done on Trader Joe in the form of an LP. It swaps those LPs
/// to a token of choice and sends it to the JoeBar
contract MoneyMaker is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IJoeFactory public immutable factory;

    address public immutable bar;
    address private immutable wavax;
    /// @notice Any ERC20
    address public tokenTo;
    /// @notice In basis points aka parts per 10,000 so 5000 is 50%, cap of 50%, default is 0
    uint256 public devCut = 0;
    address public devAddr;

    // @notice Set of addresses that can perform certain functions
    EnumerableSet.AddressSet private _isAuth;

    modifier onlyAuth() {
        require(_isAuth.contains(_msgSender()), "MoneyMaker: FORBIDDEN");
        _;
    }

    /// @dev Maps a token `token` to another token `bridge` so that it uses `token/bridge` pair to convert token
    mapping(address => address) internal _bridges;

    event AddAuthorizedAddress(address indexed _addr);
    event RemoveAuthorizedAddress(address indexed _addr);
    event SetDevAddr(address _addr);
    event SetDevCut(uint256 _amount);
    event SetTokenTo(address _tokenTo);
    event LogBridgeSet(address indexed token, address indexed oldBridge, address indexed bridge);
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountTOKEN
    );

    /// @notice Constructor
    /// @param _factory The address of JoeFactory
    /// @param _bar The address of JoeBar
    /// @param _tokenTo The address of the token we want to convert to
    /// @param _wavax The address of wavax
    constructor(
        address _factory,
        address _bar,
        address _tokenTo,
        address _wavax
    ) public {
        require(_factory != address(0), "MoneyMaker: factory can't be address(0)");
        require(_bar != address(0), "MoneyMaker: bar can't be address(0)");
        require(_tokenTo != address(0), "MoneyMaker: token can't be address(0)");
        require(_wavax != address(0), "MoneyMaker: wavax can't be address(0)");
        factory = IJoeFactory(_factory);
        bar = _bar;
        tokenTo = _tokenTo;
        wavax = _wavax;
        devAddr = _msgSender();
        _isAuth.add(_msgSender());
    }

    /// @notice Adds a user to the authorized addresses
    /// @param _auth The address to add
    function addAuth(address _auth) external onlyOwner {
        require(_isAuth.add(_auth), "MoneyMaker: Address is already authorized");
        emit AddAuthorizedAddress(_auth);
    }

    /// @notice Remove a user of authorized addresses
    /// @param _auth The address to remove
    function removeAuth(address _auth) external onlyOwner {
        require(_isAuth.remove(_auth), "MoneyMaker: Address is not authorized");
        emit RemoveAuthorizedAddress(_auth);
    }

    /// @notice Return the list of authorized addresses
    /// @param index Index of the returned address
    /// @return The authorized address at `index`
    function getAuth(uint256 index) external view returns (address) {
        return _isAuth.at(index);
    }

    /// @notice Return the length of authorized addresses
    /// @return The number of authorized addresses
    function lenAuth() external view returns (uint256) {
        return _isAuth.length();
    }

    /// @notice Force using `pair/bridge` pair to convert `token`
    /// @param token The address of the tokenFrom
    /// @param bridge The address of the tokenTo
    function setBridge(address token, address bridge) external onlyAuth {
        // Checks
        require(token != tokenTo && token != wavax && token != bridge, "MoneyMaker: Invalid bridge");

        // Effects
        address oldBridge = _bridges[token];
        _bridges[token] = bridge;
        emit LogBridgeSet(token, oldBridge, bridge);
    }

    /// @notice Sets dev cut, which will be sent to `devAddr`, can't be greater than 50%
    /// @param _amount The new devCut value
    function setDevCut(uint256 _amount) external onlyOwner {
        require(_amount <= 5000, "setDevCut: cut too high");
        devCut = _amount;

        emit SetDevCut(_amount);
    }

    /// @notice Sets `devAddr`, the address that will receive the `devCut`
    /// @param _addr The new dev address
    function setDevAddr(address _addr) external onlyOwner {
        require(_addr != address(0), "setDevAddr, address cannot be zero address");
        devAddr = _addr;

        emit SetDevAddr(_addr);
    }

    /// @notice Sets token that we're buying back
    /// @param _tokenTo The new token address
    function setTokenToAddress(address _tokenTo) external onlyOwner {
        require(_tokenTo != address(0), "setTokenToAddress, address cannot be zero address");
        tokenTo = _tokenTo;

        emit SetTokenTo(_tokenTo);
    }

    /// @notice Returns the `bridge` of a `token`
    /// @param token The tokenFrom address
    /// @return bridge The tokenTo address
    function bridgeFor(address token) public view returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = wavax;
        }
    }

    // C6: It's not a fool proof solution, but it prevents flash loans, so here it's ok to use tx.origin
    modifier onlyEOA() {
        // Try to make flash-loan exploit harder to do by only allowing externally owned addresses.
        require(_msgSender() == tx.origin, "MoneyMaker: must use EOA");
        _;
    }

    /// @notice Converts a pair of tokens to tokenTo
    /// @dev _convert is separate to save gas by only checking the 'onlyEOA' modifier once in case of convertMultiple
    /// @param token0 The address of the first token of the pair that will be converted
    /// @param token1 The address of the second token of the pair that will be converted
    /// @param slippage The accepted slippage, in basis points aka parts per 10,000 so 5000 is 50%
    function convert(
        address token0,
        address token1,
        uint256 slippage
    ) external onlyEOA onlyAuth {
        require(slippage < 5_000, "MoneyMaker: slippage needs to be lower than 50%");
        _convert(token0, token1, slippage);
    }

    /// @notice Converts a list of pairs of tokens to tokenTo
    /// @dev _convert is separate to save gas by only checking the 'onlyEOA' modifier once in case of convertMultiple
    /// @param token0 The list of addresses of the first token of the pairs that will be converted
    /// @param token1 The list of addresses of the second token of the pairs that will be converted
    /// @param slippage The accepted slippage, in basis points aka parts per 10,000 so 5000 is 50%
    function convertMultiple(
        address[] calldata token0,
        address[] calldata token1,
        uint256 slippage
    ) external onlyEOA onlyAuth {
        // TODO: This can be optimized a fair bit, but this is safer and simpler for now
        require(slippage < 5_000, "MoneyMaker: slippage needs to be lower than 50%");
        require(token0.length == token1.length, "MoneyMaker: arrays length don't match");

        uint256 len = token0.length;
        for (uint256 i = 0; i < len; i++) {
            _convert(token0[i], token1[i], slippage);
        }
    }

    /// @notice Converts a pair of tokens to tokenTo
    /// @dev _convert is separate to save gas by only checking the 'onlyEOA' modifier once in case of convertMultiple
    /// @param token0 The address of the first token of the pair that is currently being converted
    /// @param token1 The address of the second token of the pair that is currently being converted
    /// @param slippage The accepted slippage, in basis points aka parts per 10,000 so 5000 is 50%
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
            require(address(pair) != address(0), "MoneyMaker: Invalid pair");

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
            _msgSender(),
            token0,
            token1,
            amount0,
            amount1,
            _convertStep(token0, token1, amount0, amount1, slippage)
        );
    }

    /// @notice Used to convert two tokens to `tokenTo`, step by step, called recursively
    /// @param token0 The address of the first token
    /// @param token1 The address of the second token
    /// @param amount0 The amount of the `token0`
    /// @param amount1 The amount of the `token1`
    /// @param slippage The accepted slippage, in basis points aka parts per 10,000 so 5000 is 50%
    /// @return tokenOut The amount of token
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

    /// @notice Swaps `amountIn` `fromToken` to `toToken` and sends it to `to`, `amountOut` is required to be greater
    /// than allowed `slippage`
    /// @param fromToken The address of token that will be swapped
    /// @param toToken The address of the token that will be received
    /// @param amountIn The amount of the `fromToken`
    /// @param to The address that will receive the `toToken`
    /// @param slippage The accepted slippage, in basis points aka parts per 10,000 so 5000 is 50%
    /// @return amountOut The amount of `toToken` sent to `to`
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
        require(address(pair) != address(0), "MoneyMaker: Cannot convert");

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        (uint256 reserveInput, uint256 reserveOutput) = fromToken == pair.token0()
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        IERC20(fromToken).safeTransfer(address(pair), amountIn);
        uint256 amountInput = IERC20(fromToken).balanceOf(address(pair)).sub(reserveInput); // calculate amount that was transferred, this accounts for transfer taxes

        amountOut = JoeLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);

        {
            uint256 rest = uint256(10_000).sub(slippage);
            /// @dev We simulate the amount received if we did a swapIn and swapOut without updating the reserves,
            /// hence why we do rest^2, i.e. calculating the slippage twice cause we actually do two swaps.
            /// This allows us to catch if a pair has low liquidity
            require(
                JoeLibrary.getAmountOut(amountOut, reserveOutput, reserveInput) >=
                    amountInput.mul(rest).mul(rest).div(100_000_000),
                "MoneyMaker: Slippage caught"
            );
        }

        (uint256 amount0Out, uint256 amount1Out) = fromToken == pair.token0()
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));
        pair.swap(amount0Out, amount1Out, to, new bytes(0));
    }

    /// @notice Swaps an amount of token to another token, `tokenTo`
    /// @dev `amountOut` is required to be greater after slippage
    /// @param token The address of token that will be swapped
    /// @param amountIn The amount of the `token`
    /// @param slippage The accepted slippage, in basis points aka parts per 10,000 so 5000 is 50%
    /// @return amountOut The amount of `toToken` sent to JoeBar
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
}
