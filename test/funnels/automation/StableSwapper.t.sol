// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { Swapper, GemLike } from "src/funnels/Swapper.sol";
import { StableSwapper } from "src/funnels/automation/StableSwapper.sol";
import { SwapperCalleeUniV3 } from "src/funnels/callees/SwapperCalleeUniV3.sol";
import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";

contract StableSwapperTest is DssTest {
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(address indexed src, address indexed dst, uint128 num, uint32 hop, uint96 lot, uint96 req);
    event Swap(address indexed sender, address indexed src, address indexed dst, uint256 amt, uint256 out);

    AllocatorBuffer public buffer;
    Swapper public swapper;
    StableSwapper public stableSwapper;
    SwapperCalleeUniV3 public uniV3Callee;

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
        uniV3Callee = new SwapperCalleeUniV3(UNIV3_ROUTER);
        stableSwapper = new StableSwapper(address(swapper));

        roles.setIlkAdmin(ilk, address(this));
        roles.setRoleAction(ilk, SWAPPER_ROLE, address(swapper), swapper.swap.selector, true);
        roles.setUserRole(ilk, FACILITATOR, SWAPPER_ROLE, true);
        roles.setUserRole(ilk, address(stableSwapper), SWAPPER_ROLE, true);

        swapper.setLimits(DAI, USDC, uint96(10_000 * WAD), 3600 seconds);
        swapper.setLimits(USDC, DAI, uint96(10_000 * 10**6), 3600 seconds);

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(swapper), type(uint256).max);
        buffer.approve(DAI,  address(swapper), type(uint256).max);

        stableSwapper.rely(FACILITATOR);
        vm.startPrank(FACILITATOR); 
        stableSwapper.setConfig(DAI, USDC, 10, 360 seconds, uint96(1_000 * WAD), uint96(990 * 10**6));
        stableSwapper.setConfig(USDC, DAI, 10, 360 seconds, uint96(1_000 * 10**6), uint96(990 * WAD));
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
        checkModifier(address(stableSwapper), "StableSwapper/not-authorized", authedMethods);
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
        emit SetConfig(address(0x123), address(0x456), uint128(23), uint32(360 seconds), uint96(314), uint96(42));
        stableSwapper.setConfig(address(0x123), address(0x456), uint128(23), uint32(360 seconds), uint96(314), uint96(42));

        (uint128 num, uint32 hop, uint32 zzz, uint96 lot, uint96 req) = stableSwapper.getConfig(address(0x123), address(0x456));
        assertEq(num, 23);
        assertEq(hop, 360);
        assertEq(zzz, 0);
        assertEq(lot, 314);
        assertEq(req, 42);
    }

    function testSwapByKeeper() public {
        uint256 prevSrc = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDst = GemLike(DAI).balanceOf(address(buffer));
        (uint128 initUsdcDaiNum,,,,) = stableSwapper.getConfig(USDC, DAI);
        (uint128 initDaiUsdcNum,,,,) = stableSwapper.getConfig(DAI, USDC);
        uint32 initialTime = uint32(block.timestamp);

        vm.expectEmit(true, true, true, false);
        emit Swap(address(stableSwapper), USDC, DAI, 0, 0);
        vm.prank(KEEPER); uint256 out = stableSwapper.swap(USDC, DAI, 990 * WAD, address(uniV3Callee), USDC_DAI_PATH);

        assertGe(out, 990 * WAD);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevSrc - 1_000 * 10**6);
        assertEq(GemLike(DAI).balanceOf(address(buffer)), prevDst + out);
        assertEq(GemLike(DAI).balanceOf(address(stableSwapper)), 0);
        assertEq(GemLike(USDC).balanceOf(address(stableSwapper)), 0);
        assertEq(GemLike(DAI).balanceOf(address(swapper)), 0);
        assertEq(GemLike(USDC).balanceOf(address(swapper)), 0);
        assertEq(GemLike(DAI).balanceOf(address(uniV3Callee)), 0);
        assertEq(GemLike(USDC).balanceOf(address(uniV3Callee)), 0);
        (uint128 usdcDaiNum,, uint32 usdcDaiZzz,,) = stableSwapper.getConfig(USDC, DAI);
        assertEq(usdcDaiNum, initUsdcDaiNum - 1);
        assertEq(usdcDaiZzz, initialTime);

        vm.warp(initialTime + 180);
        vm.expectRevert("StableSwapper/too-soon");
        vm.prank(KEEPER); stableSwapper.swap(USDC, DAI, 990 * WAD, address(uniV3Callee), USDC_DAI_PATH);

        vm.warp(initialTime + 360);
        vm.prank(KEEPER); stableSwapper.swap(USDC, DAI, 990 * WAD, address(uniV3Callee), USDC_DAI_PATH);

        (usdcDaiNum,, usdcDaiZzz,,) = stableSwapper.getConfig(USDC, DAI);
        assertEq(usdcDaiNum, initUsdcDaiNum - 2);
        assertEq(usdcDaiZzz, initialTime + 360);

        prevSrc = GemLike(DAI).balanceOf(address(buffer));
        prevDst = GemLike(USDC).balanceOf(address(buffer));

        vm.expectEmit(true, true, true, false);
        emit Swap(address(stableSwapper), DAI, USDC, 0, 0);
        vm.prank(KEEPER); out = stableSwapper.swap(DAI, USDC, 990 * 10**6, address(uniV3Callee), DAI_USDC_PATH);

        assertGe(out, 990 * 10**6);
        assertEq(GemLike(DAI).balanceOf(address(buffer)), prevSrc - 1_000 * WAD);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevDst + out);
        assertEq(GemLike(DAI).balanceOf(address(stableSwapper)), 0);
        assertEq(GemLike(USDC).balanceOf(address(stableSwapper)), 0);
        assertEq(GemLike(DAI).balanceOf(address(swapper)), 0);
        assertEq(GemLike(USDC).balanceOf(address(swapper)), 0);
        assertEq(GemLike(DAI).balanceOf(address(uniV3Callee)), 0);
        assertEq(GemLike(USDC).balanceOf(address(uniV3Callee)), 0);
        (uint128 daiUsdcNum,, uint32 daiUsdcZzz,,) = stableSwapper.getConfig(DAI, USDC);
        assertEq(daiUsdcNum, initDaiUsdcNum - 1);
        assertEq(daiUsdcZzz, initialTime + 360);
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

    function testSwapExceedingNum() public {
        vm.expectRevert("StableSwapper/exceeds-num");
        vm.prank(KEEPER); stableSwapper.swap(USDC, USDC, 0, address(uniV3Callee), USDC_DAI_PATH);
    }

    function testSwapWithMinTooSmall() public {
        (,,,, uint96 req) = stableSwapper.getConfig(USDC, DAI);
        vm.expectRevert("StableSwapper/min-too-small");
        vm.prank(KEEPER); stableSwapper.swap(USDC, DAI, req - 1, address(uniV3Callee), USDC_DAI_PATH);
    }


    function testEnumeratePairs() public {
        assertEq(stableSwapper.numPairs(), 2);
        assertEq(stableSwapper.pairAt(0).src, DAI);
        assertEq(stableSwapper.pairAt(0).dst, USDC);
        assertEq(stableSwapper.pairAt(1).src, USDC);
        assertEq(stableSwapper.pairAt(1).dst, DAI);

        vm.prank(FACILITATOR); stableSwapper.setConfig(DAI, USDC, 10, 720 seconds, uint96(1_000 * WAD), uint96(990 * 10**6)); // just changing hop

        assertEq(stableSwapper.numPairs(), 2);
        assertEq(stableSwapper.pairAt(0).src, DAI);
        assertEq(stableSwapper.pairAt(0).dst, USDC);
        assertEq(stableSwapper.pairAt(1).src, USDC);
        assertEq(stableSwapper.pairAt(1).dst, DAI);

        vm.prank(FACILITATOR); stableSwapper.setConfig(DAI, USDC, 0, 0, 0, 0);

        assertEq(stableSwapper.numPairs(), 1);
        assertEq(stableSwapper.pairAt(0).src, USDC);
        assertEq(stableSwapper.pairAt(0).dst, DAI);
        vm.expectRevert();
        stableSwapper.pairAt(1);

        vm.prank(FACILITATOR); stableSwapper.setConfig(USDC, DAI, 0, 0, 0, 0);

        assertEq(stableSwapper.numPairs(), 0);
        vm.expectRevert();
        stableSwapper.pairAt(0);

        vm.prank(FACILITATOR); stableSwapper.setConfig(DAI, USDC, 1, 0, uint96(1_000 * WAD), uint96(990 * 10**6));
        vm.prank(FACILITATOR); stableSwapper.setConfig(USDC, DAI, 2, 0, uint96(1_000 * 10**6), uint96(990 * WAD));

        assertEq(stableSwapper.numPairs(), 2);
        assertEq(stableSwapper.pairAt(0).src, DAI);
        assertEq(stableSwapper.pairAt(0).dst, USDC);
        assertEq(stableSwapper.pairAt(1).src, USDC);
        assertEq(stableSwapper.pairAt(1).dst, DAI);

        vm.prank(KEEPER); stableSwapper.swap(USDC, DAI, 0, address(uniV3Callee), USDC_DAI_PATH); // reduce num from 2 to 1

        assertEq(stableSwapper.numPairs(), 2);
        assertEq(stableSwapper.pairAt(0).src, DAI);
        assertEq(stableSwapper.pairAt(0).dst, USDC);
        assertEq(stableSwapper.pairAt(1).src, USDC);
        assertEq(stableSwapper.pairAt(1).dst, DAI);

        vm.prank(KEEPER); stableSwapper.swap(USDC, DAI, 0, address(uniV3Callee), USDC_DAI_PATH); // reduce num from 1 to 0

        assertEq(stableSwapper.numPairs(), 1);
        assertEq(stableSwapper.pairAt(0).src, DAI);
        assertEq(stableSwapper.pairAt(0).dst, USDC);
        vm.expectRevert();
        stableSwapper.pairAt(1);

        vm.prank(KEEPER); stableSwapper.swap(DAI, USDC, 0, address(uniV3Callee), DAI_USDC_PATH); // reduce num from 1 to 0

        assertEq(stableSwapper.numPairs(), 0);
        vm.expectRevert();
        stableSwapper.pairAt(0);
    }
}
