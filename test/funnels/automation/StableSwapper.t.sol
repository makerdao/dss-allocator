// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { Swapper, GemLike } from "src/funnels/Swapper.sol";
import { StableSwapper } from "src/funnels/automation/StableSwapper.sol";
import { UniV3SwapperCallee } from "src/funnels/callees/UniV3SwapperCallee.sol";
import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { TestUtils } from "test/utils/TestUtils.sol";

contract StableSwapperTest is DssTest, TestUtils {
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(address indexed src, address indexed dst, uint128 count, uint64 hop, uint128 lot, uint128 reqOut);
    event Swap(address indexed sender, address indexed src, address indexed dst, uint256 amt, uint256 out);

    AllocatorBuffer public buffer;
    Swapper public swapper;
    StableSwapper public stableSwapper;
    UniV3SwapperCallee public uniV3Callee;

    bytes32 constant ilk = "aaa";
    bytes constant USDC_DAI_PATH = abi.encodePacked(USDC, uint24(100), DAI);
    bytes constant DAI_USDC_PATH = abi.encodePacked(DAI, uint24(100), USDC);

    address constant DAI          = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC         = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address constant FACILITATOR = address(0x1337);
    address constant KEEPER      = address(0xb0b);

    uint8 constant SWAPPER_ROLE = uint8(1);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        buffer = new AllocatorBuffer();
        AllocatorRoles roles = new AllocatorRoles();
        swapper = new Swapper(address(roles), ilk, address(buffer));
        uniV3Callee = new UniV3SwapperCallee(UNIV3_ROUTER);
        stableSwapper = new StableSwapper(address(swapper));

        roles.setIlkAdmin(ilk, address(this));
        roles.setRoleAction(ilk, SWAPPER_ROLE, address(swapper), swapper.swap.selector, true);
        roles.setUserRole(ilk, FACILITATOR, SWAPPER_ROLE, true);
        roles.setUserRole(ilk, address(stableSwapper), SWAPPER_ROLE, true);

        swapper.setLimits(DAI, USDC, 3600 seconds, uint128(10_000 * WAD));
        swapper.setLimits(USDC, DAI, 3600 seconds, uint128(10_000 * 10**6));

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(swapper), type(uint256).max);
        buffer.approve(DAI,  address(swapper), type(uint256).max);

        stableSwapper.rely(FACILITATOR);
        vm.startPrank(FACILITATOR); 
        stableSwapper.setConfig(DAI, USDC, 10, 3600 seconds, uint112(10_000 * WAD), uint112(9900 * 10**6));
        stableSwapper.setConfig(USDC, DAI, 10, 3600 seconds, uint96(10_000 * 10**6),  uint112(9900 * WAD));
        stableSwapper.kiss(KEEPER);
        vm.stopPrank();
    }

    function testConstructor() public {
        StableSwapper s = new StableSwapper(address(0xABC));
        assertEq(address(s.swapper()),  address(0xABC));
        assertEq(s.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(stableSwapper), "StableSwapper");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](3);
        authedMethods[0] = stableSwapper.kiss.selector;
        authedMethods[1] = stableSwapper.diss.selector;
        authedMethods[2] = stableSwapper.setConfig.selector;

        vm.startPrank(address(0xBEEF));
        checkModifierForLargeArgs(address(stableSwapper), "StableSwapper/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testKissDiss() public {
        address testAddress = address(0x123);

        assertEq(stableSwapper.buds(testAddress), 0);
        vm.expectEmit(true, true, true, true);
        emit Kiss(testAddress);
        stableSwapper.kiss(testAddress);
        assertEq(stableSwapper.buds(testAddress), 1);
        vm.expectEmit(true, true, true, true);
        emit Diss(testAddress);
        stableSwapper.diss(testAddress);
        assertEq(stableSwapper.buds(testAddress), 0);
    }

    function testSetConfig() public {
        vm.expectEmit(true, true, true, true);
        emit SetConfig(address(0x123), address(0x456), uint128(23), uint64(3600 seconds), uint128(314), uint128(42));
        stableSwapper.setConfig(address(0x123), address(0x456), uint128(23), uint64(3600 seconds), uint128(314), uint128(42));

        (uint128 count, uint64 hop,, uint128 lot, uint128 reqOut) = stableSwapper.configs(address(0x123), address(0x456));
        assertEq(count, 23);
        assertEq(hop, 3600);
        assertEq(lot, 314);
        assertEq(reqOut, 42);
    }

    function testSwapByKeeper() public {
        uint256 prevSrc = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDst = GemLike(DAI).balanceOf(address(buffer));
        (uint128 prevUsdcDaiCount,,,,) = stableSwapper.configs(USDC, DAI);
        (uint128 prevDaiUsdcCount,,,,) = stableSwapper.configs(DAI, USDC);

        vm.expectEmit(true, true, true, false);
        emit Swap(address(stableSwapper), USDC, DAI, 0, 0);
        vm.prank(KEEPER); uint256 out = stableSwapper.swap(USDC, DAI, 9900 * WAD, address(uniV3Callee), USDC_DAI_PATH);

        assertGe(out, 9900 * WAD);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevSrc - 10_000 * 10**6);
        assertEq(GemLike(DAI).balanceOf(address(buffer)), prevDst + out);
        assertEq(GemLike(DAI).balanceOf(address(stableSwapper)), 0);
        assertEq(GemLike(USDC).balanceOf(address(stableSwapper)), 0);
        assertEq(GemLike(DAI).balanceOf(address(swapper)), 0);
        assertEq(GemLike(USDC).balanceOf(address(swapper)), 0);
        assertEq(GemLike(DAI).balanceOf(address(uniV3Callee)), 0);
        assertEq(GemLike(USDC).balanceOf(address(uniV3Callee)), 0);
        (uint128 currentUsdcDaiCount,,,,) = stableSwapper.configs(USDC, DAI);
        assertEq(currentUsdcDaiCount, prevUsdcDaiCount - 1);

        vm.warp(block.timestamp + 3600);
        prevSrc = GemLike(DAI).balanceOf(address(buffer));
        prevDst = GemLike(USDC).balanceOf(address(buffer));

        vm.expectEmit(true, true, true, false);
        emit Swap(address(stableSwapper), DAI, USDC, 0, 0);
        vm.prank(KEEPER); out = stableSwapper.swap(DAI, USDC, 9900 * 10**6, address(uniV3Callee), DAI_USDC_PATH);

        assertGe(out, 9900 * 10**6);
        assertEq(GemLike(DAI).balanceOf(address(buffer)), prevSrc - 10_000 * WAD);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevDst + out);
        assertEq(GemLike(DAI).balanceOf(address(stableSwapper)), 0);
        assertEq(GemLike(USDC).balanceOf(address(stableSwapper)), 0);
        assertEq(GemLike(DAI).balanceOf(address(swapper)), 0);
        assertEq(GemLike(USDC).balanceOf(address(swapper)), 0);
        assertEq(GemLike(DAI).balanceOf(address(uniV3Callee)), 0);
        assertEq(GemLike(USDC).balanceOf(address(uniV3Callee)), 0);
        (uint128 currentDaiUsdcCount,,,,) = stableSwapper.configs(DAI, USDC);
        assertEq(currentDaiUsdcCount, prevDaiUsdcCount - 1);
    }

    function testSwapMinZero() public {
        vm.expectEmit(true, true, true, false);
        emit Swap(address(stableSwapper), USDC, DAI, 0, 0);
        vm.prank(KEEPER); stableSwapper.swap(USDC, DAI, 0, address(uniV3Callee), USDC_DAI_PATH);
    }

    function testSwapNonKeeper() public {
        assertEq(stableSwapper.buds(address(this)), 0);
        vm.expectRevert("StableSwapper/non-keeper");
        stableSwapper.swap(USDC, DAI, 9900 * WAD, address(uniV3Callee), USDC_DAI_PATH);
    }

    function testSwapExceedingCount() public {
        vm.expectRevert("StableSwapper/exceeds-count");
        vm.prank(KEEPER); stableSwapper.swap(USDC, USDC, 0, address(uniV3Callee), USDC_DAI_PATH);
    }

    function testSwapWithMinTooSmall() public {
        (,,,, uint128 reqOut) = stableSwapper.configs(USDC, DAI);
        vm.expectRevert("StableSwapper/min-too-small");
        vm.prank(KEEPER); stableSwapper.swap(USDC, DAI, reqOut - 1, address(uniV3Callee), USDC_DAI_PATH);
    }
}
