// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IPair.sol";
import "./interfaces/IBar.sol";

interface IMasterChef {
    function userInfo(uint256 pid, address owner) external view returns (uint256, uint256);
}

contract JoeVote {
    using SafeMath for uint256;

    IPair pair; // JOE-AVAX LP
    IBar bar;
    IERC20 joe;
    IMasterChef chef;
    uint256 pid; // Pool ID of the JOE-AVAX LP in MasterChefV2

    function name() public pure returns (string memory) {
        return "JoeVote";
    }

    function symbol() public pure returns (string memory) {
        return "JOEVOTE";
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    constructor(
        address _pair,
        address _bar,
        address _joe,
        address _chef,
        uint256 _pid
    ) public {
        pair = IPair(_pair);
        bar = IBar(_bar);
        joe = IERC20(_joe);
        chef = IMasterChef(_chef);
        pid = _pid;
    }

    function totalSupply() public view returns (uint256) {
        (uint256 lp_totalJoe, , ) = pair.getReserves();
        uint256 xjoe_totalJoe = joe.balanceOf(address(bar));

        return lp_totalJoe.mul(2).add(xjoe_totalJoe);
    }

    function balanceOf(address owner) public view returns (uint256) {
        //////////////////////////
        // Get balance from LPs //
        //////////////////////////
        uint256 lp_totalJoe = joe.balanceOf(address(pair));
        uint256 lp_total = pair.totalSupply();
        uint256 lp_balance = pair.balanceOf(owner);

        // Add staked balance
        (uint256 lp_stakedBalance, ) = chef.userInfo(pid, owner);
        lp_balance = lp_balance.add(lp_stakedBalance);

        // LP voting power is 2x the users JOE share in the pool.
        uint256 lp_powah = lp_totalJoe.mul(lp_balance).div(lp_total).mul(2);

        ///////////////////////////
        // Get balance from xJOE //
        ///////////////////////////

        uint256 xjoe_balance = bar.balanceOf(owner);
        uint256 xjoe_total = bar.totalSupply();
        uint256 xjoe_totalJoe = joe.balanceOf(address(bar));

        // xJOE voting power is the users JOE share in the bar
        uint256 xjoe_powah = xjoe_totalJoe.mul(xjoe_balance).div(xjoe_total);

        //////////////////////////
        // Get balance from JOE //
        //////////////////////////

        uint256 joe_balance = joe.balanceOf(owner);

        return lp_powah.add(xjoe_powah).add(joe_balance);
    }

    function allowance(address, address) public pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) public pure returns (bool) {
        return false;
    }

    function approve(address, uint256) public pure returns (bool) {
        return false;
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure returns (bool) {
        return false;
    }
}
