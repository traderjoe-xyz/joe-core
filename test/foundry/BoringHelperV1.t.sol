// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "forge-std/Test.sol";

import "contracts/boringcrypto/BoringHelperV1.sol";

contract testBoringHelperV1 is Test {
    BoringHelperV1 constant boringHelper = BoringHelperV1(0x1dd4D86180EEe39ac4fB35ECa67CACF608Ab5741);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 37292546);
    }

    function test_PollPools() public {
        uint256[] memory pids = new uint256[](1);

        vm.expectRevert("SafeMath: division by zero");
        boringHelper.pollPools(address(this), pids);

        BoringHelperV1 newBoringHelper = new BoringHelperV1(
            boringHelper.chef(),
            boringHelper.maker(),
            boringHelper.joe(),
            boringHelper.WAVAX(),
            boringHelper.joeFactory(),
            boringHelper.pangolinFactory(),
            boringHelper.bar()
        );

        newBoringHelper.pollPools(address(this), pids);
    }
}
