// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.6;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import "../../contracts/StableJoeStaking.sol";

contract TestUpgradeSJoe is Test {
    address constant joe = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;
    address constant wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    address constant owner = 0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2;
    address constant joePOL = 0x3876183b75916e20d2ADAB202D1A3F9e9bf320ad;

    ProxyAdmin constant defaultProxyAdmin = ProxyAdmin(0x246ABeC8f8a542E892934232DB3Fd97A61E3193c);
    StableJoeStaking constant sjoe = StableJoeStaking(0x1a731B2299E22FbAC282E7094EdA41046343Cb51);

    StableJoeStaking imp;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 35393036);

        imp = new StableJoeStaking(IERC20Upgradeable(joe));
    }

    function test_CantInitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        imp.initialize(IERC20Upgradeable(address(0)), address(0), 0);

        _upgrade();

        vm.expectRevert("Initializable: contract is already initialized");
        imp.initialize(IERC20Upgradeable(address(0)), address(0), 0);
    }

    function test_VerifyStorage() public {
        bytes32[] memory slots = new bytes32[](50);

        uint256 i;

        slots[i++] = bytes32(uint256(uint160(address(sjoe.joe()))));
        slots[i++] = bytes32(sjoe.internalJoeBalance());

        uint256 l = sjoe.rewardTokensLength();
        slots[i++] = bytes32(l);

        for (uint256 ii = 0; ii < l; ii++) {
            IERC20Upgradeable token = sjoe.rewardTokens(ii);

            slots[i++] = bytes32(uint256(uint160(address(token))));
            slots[i++] = bytes32(sjoe.lastRewardBalance(token));
            slots[i++] = bytes32(sjoe.accRewardPerShare(token));

            (uint256 amount, uint256 rewardDebt) = sjoe.getUserInfo(joePOL, token);

            assert(amount > 0);
            assert(rewardDebt > 0);

            slots[i++] = bytes32(amount);
            slots[i++] = bytes32(rewardDebt);
        }

        slots[i++] = bytes32(sjoe.DEPOSIT_FEE_PERCENT_PRECISION());
        slots[i++] = bytes32(sjoe.ACC_REWARD_PER_SHARE_PRECISION());

        _upgrade();

        uint256 j;

        assertEq(slots[j++], bytes32(uint256(uint160(address(sjoe.joe())))), "test_VerifyStorage::1");
        assertEq(slots[j++], bytes32(sjoe.internalJoeBalance()), "test_VerifyStorage::2");
        assertEq(slots[j++], bytes32(sjoe.rewardTokensLength()), "test_VerifyStorage::3");

        for (uint256 jj = 0; jj < l; jj++) {
            IERC20Upgradeable token = sjoe.rewardTokens(jj);

            assertEq(slots[j++], bytes32(uint256(uint160(address(token)))), "test_VerifyStorage::4");
            assertEq(slots[j++], bytes32(sjoe.lastRewardBalance(token)), "test_VerifyStorage::5");
            assertEq(slots[j++], bytes32(sjoe.accRewardPerShare(token)), "test_VerifyStorage::6");

            (uint256 amount, uint256 rewardDebt) = sjoe.getUserInfo(joePOL, token);

            assertEq(slots[j++], bytes32(amount), "test_VerifyStorage::7");
            assertEq(slots[j++], bytes32(rewardDebt), "test_VerifyStorage::8");
        }

        assertEq(slots[j++], bytes32(sjoe.DEPOSIT_FEE_PERCENT_PRECISION()), "test_VerifyStorage::9");
        assertEq(slots[j++], bytes32(sjoe.ACC_REWARD_PER_SHARE_PRECISION()), "test_VerifyStorage::10");

        assertEq(j, i, "test_VerifyStorage::11");
    }

    function test_Sweep() public {
        _upgrade();

        vm.expectRevert("Ownable: caller is not the owner");
        sjoe.sweep(IERC20Upgradeable(joe), address(this));

        vm.startPrank(owner);

        vm.expectRevert("StableJoeStaking: token can't be swept");
        sjoe.sweep(IERC20Upgradeable(joe), address(this));

        IERC20Upgradeable rewardToken = IERC20Upgradeable(sjoe.rewardTokens(0));

        vm.expectRevert("StableJoeStaking: token can't be swept");
        sjoe.sweep(rewardToken, address(this));

        vm.expectRevert("StableJoeStaking: can't sweep 0");
        sjoe.sweep(IERC20Upgradeable(wavax), address(this));

        deal(wavax, address(sjoe), 1e18);

        assertEq(IERC20Upgradeable(wavax).balanceOf(address(this)), 0, "test_Sweep::1");

        sjoe.sweep(IERC20Upgradeable(wavax), address(this));

        assertEq(IERC20Upgradeable(wavax).balanceOf(address(this)), 1e18, "test_Sweep::2");

        sjoe.removeRewardToken(rewardToken);

        assertEq(rewardToken.balanceOf(address(this)), 0, "test_Sweep::3");

        sjoe.sweep(rewardToken, address(this));

        assertGt(rewardToken.balanceOf(address(this)), 0, "test_Sweep::4");

        vm.stopPrank();
    }

    function test_ReAddRewardToken() public {
        _upgrade();

        IERC20Upgradeable rewardToken = IERC20Upgradeable(sjoe.rewardTokens(0));

        vm.startPrank(owner);

        sjoe.removeRewardToken(rewardToken);

        vm.expectRevert("StableJoeStaking: reward token can't be re-added");
        sjoe.addRewardToken(rewardToken);

        sjoe.addRewardToken(IERC20Upgradeable(wavax));

        sjoe.removeRewardToken(IERC20Upgradeable(wavax));

        sjoe.addRewardToken(IERC20Upgradeable(wavax)); // Safe as wavax was never updated

        vm.expectRevert("StableJoeStaking: reward token can't be re-added");
        sjoe.addRewardToken(rewardToken);

        vm.stopPrank();
    }

    function _upgrade() internal {
        vm.prank(owner);
        defaultProxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(sjoe))), address(imp));
    }
}
