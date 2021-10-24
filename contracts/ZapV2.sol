// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

/*
 * Trader Joe
 * MIT License; modified from PancakeBunny
 *
 */

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./traderjoe/interfaces/IJoePair.sol";
import "./traderjoe/interfaces/IJoeRouter02.sol";
import "./traderjoe/interfaces/IWAVAX.sol";

contract ZapV2 is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== CONSTANT VARIABLES ========== */

    address public JOE;
    address public constant USDT = 0xde3A24028580884448a5397872046a019649b084;
    address public constant DAI = 0xbA7dEebBFC5fA1100Fb055a87773e1E99Cd3507a;
    address public constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    IJoeRouter02 private ROUTER;

    /* ========== STATE VARIABLES ========== */

    mapping(address => bool) private notLP;
    mapping(address => address) private routePairAddresses;
    address[] public tokens;

    /* ========== INITIALIZER ========== */

    function initialize(address _joe, address _router) external initializer {
        __Ownable_init();
        require(owner() != address(0), "ZapV2ETH: owner must be set");

        JOE = _joe;
        ROUTER = IJoeRouter02(_router);
        setNotLP(WAVAX);
        setNotLP(USDT);
        setNotLP(JOE);
        setNotLP(DAI);
    }

    receive() external payable {}

    /* ========== View Functions ========== */

    function isLP(address _address) public view returns (bool) {
        return !notLP[_address];
    }

    function routePair(address _address) external view returns (address) {
        return routePairAddresses[_address];
    }

    /* ========== External Functions ========== */

    function zapInToken(
        address _from,
        uint256 amount,
        address _to
    ) external {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        if (isLP(_to)) {
            IJoePair pair = IJoePair(_to);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (_from == token0 || _from == token1) {
                // swap half amount for other
                address other = _from == token0 ? token1 : token0;
                _approveTokenIfNeeded(other);
                uint256 sellAmount = amount.div(2);
                uint256 otherAmount = _swap(_from, sellAmount, other, address(this));
                ROUTER.addLiquidity(
                    _from,
                    other,
                    amount.sub(sellAmount),
                    otherAmount,
                    0,
                    0,
                    msg.sender,
                    block.timestamp
                );
            } else {
                uint256 avaxAmount = _swapTokenForAVAX(_from, amount, address(this));
                _swapAVAXToLP(_to, avaxAmount, msg.sender);
            }
        } else {
            _swap(_from, amount, _to, msg.sender);
        }
    }

    function zapIn(address _to) external payable {
        _swapAVAXToLP(_to, msg.value, msg.sender);
    }

    function zapOut(address _from, uint256 amount) external {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        if (!isLP(_from)) {
            _swapTokenForAVAX(_from, amount, msg.sender);
        } else {
            IJoePair pair = IJoePair(_from);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (token0 == WAVAX || token1 == WAVAX) {
                ROUTER.removeLiquidityAVAX(
                    token0 != WAVAX ? token0 : token1,
                    amount,
                    0,
                    0,
                    msg.sender,
                    block.timestamp
                );
            } else {
                ROUTER.removeLiquidity(token0, token1, amount, 0, 0, msg.sender, block.timestamp);
            }
        }
    }

    /* ========== Private Functions ========== */

    function _approveTokenIfNeeded(address token) private {
        if (IERC20(token).allowance(address(this), address(ROUTER)) == 0) {
            IERC20(token).safeApprove(address(ROUTER), uint256(~0));
        }
    }

    function _swapAVAXToLP(
        address lp,
        uint256 amount,
        address receiver
    ) private {
        if (!isLP(lp)) {
            _swapAVAXForToken(lp, amount, receiver);
        } else {
            // lp
            IJoePair pair = IJoePair(lp);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (token0 == WAVAX || token1 == WAVAX) {
                address token = token0 == WAVAX ? token1 : token0;
                uint256 swapValue = amount.div(2);
                uint256 tokenAmount = _swapAVAXForToken(token, swapValue, address(this));

                _approveTokenIfNeeded(token);
                ROUTER.addLiquidityAVAX{value: amount.sub(swapValue)}(
                    token,
                    tokenAmount,
                    0,
                    0,
                    receiver,
                    block.timestamp
                );
            } else {
                uint256 swapValue = amount.div(2);
                uint256 token0Amount = _swapAVAXForToken(token0, swapValue, address(this));
                uint256 token1Amount = _swapAVAXForToken(token1, amount.sub(swapValue), address(this));

                _approveTokenIfNeeded(token0);
                _approveTokenIfNeeded(token1);
                ROUTER.addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, receiver, block.timestamp);
            }
        }
    }

    function _swapAVAXForToken(
        address token,
        uint256 value,
        address receiver
    ) private returns (uint256) {
        address[] memory path;

        if (routePairAddresses[token] != address(0)) {
            path = new address[](3);
            path[0] = WAVAX;
            path[1] = routePairAddresses[token];
            path[2] = token;
        } else {
            path = new address[](2);
            path[0] = WAVAX;
            path[1] = token;
        }

        uint256[] memory amounts = ROUTER.swapExactAVAXForTokens{value: value}(0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swapTokenForAVAX(
        address token,
        uint256 amount,
        address receiver
    ) private returns (uint256) {
        address[] memory path;
        if (routePairAddresses[token] != address(0)) {
            path = new address[](3);
            path[0] = token;
            path[1] = routePairAddresses[token];
            path[2] = WAVAX;
        } else {
            path = new address[](2);
            path[0] = token;
            path[1] = WAVAX;
        }

        uint256[] memory amounts = ROUTER.swapExactTokensForAVAX(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swap(
        address _from,
        uint256 amount,
        address _to,
        address receiver
    ) private returns (uint256) {
        address intermediate = routePairAddresses[_from];
        if (intermediate == address(0)) {
            intermediate = routePairAddresses[_to];
        }

        address[] memory path;
        if (intermediate != address(0) && (_from == WAVAX || _to == WAVAX)) {
            // [WAVAX, BUSD, VAI] or [VAI, BUSD, WAVAX]
            path = new address[](3);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = _to;
        } else if (intermediate != address(0) && (_from == intermediate || _to == intermediate)) {
            // [VAI, BUSD] or [BUSD, VAI]
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_from] == routePairAddresses[_to]) {
            // [VAI, DAI] or [VAI, USDC]
            path = new address[](3);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = _to;
        } else if (
            routePairAddresses[_from] != address(0) &&
            routePairAddresses[_to] != address(0) &&
            routePairAddresses[_from] != routePairAddresses[_to]
        ) {
            // routePairAddresses[xToken] = xRoute
            // [VAI, BUSD, WAVAX, xRoute, xToken]
            path = new address[](5);
            path[0] = _from;
            path[1] = routePairAddresses[_from];
            path[2] = WAVAX;
            path[3] = routePairAddresses[_to];
            path[4] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_from] != address(0)) {
            // [VAI, BUSD, WAVAX, BUNNY]
            path = new address[](4);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = WAVAX;
            path[3] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_to] != address(0)) {
            // [BUNNY, WAVAX, BUSD, VAI]
            path = new address[](4);
            path[0] = _from;
            path[1] = WAVAX;
            path[2] = intermediate;
            path[3] = _to;
        } else if (_from == WAVAX || _to == WAVAX) {
            // [WAVAX, BUNNY] or [BUNNY, WAVAX]
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            // [USDT, BUNNY] or [BUNNY, USDT]
            path = new address[](3);
            path[0] = _from;
            path[1] = WAVAX;
            path[2] = _to;
        }

        uint256[] memory amounts = ROUTER.swapExactTokensForTokens(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setRoutePairAddress(address asset, address route) external onlyOwner {
        routePairAddresses[asset] = route;
    }

    function setNotLP(address token) public onlyOwner {
        bool needPush = notLP[token] == false;
        notLP[token] = true;
        if (needPush) {
            tokens.push(token);
        }
    }

    function removeToken(uint256 i) external onlyOwner {
        address token = tokens[i];
        notLP[token] = false;
        tokens[i] = tokens[tokens.length - 1];
        tokens.pop();
    }

    function sweep() external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == address(0)) continue;
            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount > 0) {
                if (token == WAVAX) {
                    IWAVAX(token).withdraw(amount);
                } else {
                    _swapTokenForAVAX(token, amount, owner());
                }
            }
        }

        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(owner()).transfer(balance);
        }
    }

    function withdraw(address token) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }

        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}
