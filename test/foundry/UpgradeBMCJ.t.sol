// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import "../../contracts/BoostedMasterChefJoe.sol";

contract TestUpgradeBMCJ is Test {
    ProxyAdmin proxyAdmin = ProxyAdmin(0x246ABeC8f8a542E892934232DB3Fd97A61E3193c);
    BoostedMasterChefJoe proxy = BoostedMasterChefJoe(0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F);

    address ms = 0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 37289196);
    }

    function test_Upgrade() public {
        uint256 previousTotalAllocPoint = proxy.totalAllocPoint();

        vm.expectRevert("SafeMath: division by zero");
        proxy.massUpdatePools();

        vm.expectRevert("SafeMath: division by zero");
        proxy.joePerSec();

        address newImpl = address(new BoostedMasterChefJoe());

        vm.prank(ms);
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(proxy))), newImpl);

        assertEq(proxy.joePerSec(), 0);
        assertEq(proxy.totalAllocPoint(), previousTotalAllocPoint);

        proxy.massUpdatePools();
    }
}
