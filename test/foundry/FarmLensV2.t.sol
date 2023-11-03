// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "forge-std/Test.sol";

import "../../contracts/traderjoe/FarmLensV2.sol";

contract testFarmLensV2 is Test {
    FarmLensV2 constant lens = FarmLensV2(0xF16d25Eba0D8E51cEAF480141bAf577aE55bfdd2);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 37292546);
    }

    function test_GetAllFarmData() public {
        vm.expectRevert("SafeMath: division by zero");
        lens.getAllFarmData(new uint256[](1), new uint256[](1), new uint256[](1), address(this));

        FarmLensV2 newLens = new FarmLensV2(
            lens.joe(),
            lens.wavax(),
            lens.wavaxUsdte(),
            lens.wavaxUsdce(),
            lens.wavaxUsdc(),
            lens.joeFactory(),
            lens.chefv2(),
            lens.chefv3(),
            lens.bmcj()
        );

        newLens.getAllFarmData(new uint256[](1), new uint256[](1), new uint256[](1), address(this));
    }
}
