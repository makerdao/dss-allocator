// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { Swapper } from "src/funnels/Swapper.sol";
import { UniV3SwapperCallee } from "src/funnels/callees/UniV3SwapperCallee.sol";
import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external;
}

contract CalleeMock is DssTest {
    function swap(address src, address dst, uint256 amt, uint256, address to, bytes calldata) external {
        GemLike(src).transfer(address(0xDEAD), amt);
        deal(dst, address(this), amt, true);
        GemLike(dst).transfer(to, amt);
    }
}

contract SwapperTest is DssTest {
    event SetLimits(address indexed gem0, address indexed gem1, uint64 hop, uint128 cap);
    event Swap(address indexed sender, address indexed src, address indexed dst, uint256 amt, uint256 out);

    AllocatorRoles public roles;
    AllocatorBuffer public buffer;
    Swapper public swapper;
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
        roles = new AllocatorRoles();
        swapper = new Swapper(address(roles), ilk, address(buffer));
        uniV3Callee = new UniV3SwapperCallee(UNIV3_ROUTER);

        roles.setIlkAdmin(ilk, address(this));
        roles.setRoleAction(ilk, SWAPPER_ROLE, address(swapper), swapper.swap.selector, true);
        roles.setUserRole(ilk, FACILITATOR, SWAPPER_ROLE, true);

        swapper.setLimits(DAI, USDC, 3600 seconds, uint128(10_000 * WAD));
        swapper.setLimits(USDC, DAI, 3600 seconds, uint128(10_000 * 10**6));

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(swapper), type(uint256).max);
        buffer.approve(DAI,  address(swapper), type(uint256).max);
    }

    function testConstructor() public {
        Swapper s = new Swapper(address(0xBEEF), "SubDAO 1", address(0xAAA));
        assertEq(address(s.roles()),  address(0xBEEF));
        assertEq(s.ilk(), "SubDAO 1");
        assertEq(s.buffer(), address(0xAAA));
        assertEq(s.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(swapper), "Swapper");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](2);
        authedMethods[0] = swapper.setLimits.selector;
        authedMethods[1] = swapper.swap.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(swapper), "Swapper/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testSetLimits() public {
        vm.expectEmit(true, true, true, true);
        emit SetLimits(address(1), address(2), 3, 4);
        vm.prank(address(this)); swapper.setLimits(address(1), address(2), 3, 4);
        (uint64 hop, uint64 zzz, uint128 cap) = swapper.limits(address(1), address(2));
        assertEq(hop, 3);
        assertEq(zzz, 0);
        assertEq(cap, 4);
    }

    function testRoles() public {
        vm.expectRevert("Swapper/not-authorized");
        vm.prank(address(0xBEEF)); swapper.setLimits(address(0), address(0), 0, 0);
        roles.setRoleAction(ilk, uint8(0xF1), address(swapper), bytes4(keccak256("setLimits(address,address,uint64,uint128)")), true);
        roles.setUserRole(ilk, address(0xBEEF), uint8(0xF1), true);
        vm.prank(address(0xBEEF)); swapper.setLimits(address(0), address(0), 0, 0);
    }

    function testSwap() public {
        uint256 prevSrc = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDst = GemLike(DAI).balanceOf(address(buffer));

        vm.expectEmit(true, true, true, false);
        emit Swap(FACILITATOR, USDC, DAI, 10_000 * 10**6, 0);
        vm.prank(FACILITATOR); uint256 out = swapper.swap(USDC, DAI, 10_000 * 10**6, 9900 * WAD, address(uniV3Callee), USDC_DAI_PATH);

        assertGe(out, 9900 * WAD);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevSrc - 10_000 * 10**6);
        assertEq(GemLike(DAI).balanceOf(address(buffer)), prevDst + out);
        assertEq(GemLike(DAI).balanceOf(address(swapper)), 0);
        assertEq(GemLike(USDC).balanceOf(address(swapper)), 0);
        assertEq(GemLike(DAI).balanceOf(address(uniV3Callee)), 0);
        assertEq(GemLike(USDC).balanceOf(address(uniV3Callee)), 0);

        prevSrc = GemLike(DAI).balanceOf(address(buffer));
        prevDst = GemLike(USDC).balanceOf(address(buffer));

        vm.expectEmit(true, true, true, false);
        emit Swap(FACILITATOR, DAI, USDC, 10_000 * WAD, 0);
        vm.prank(FACILITATOR); out = swapper.swap(DAI, USDC, 10_000 * WAD, 9900 * 10**6, address(uniV3Callee), DAI_USDC_PATH);
        
        assertGe(out, 9900 * 10**6);
        assertEq(GemLike(DAI).balanceOf(address(buffer)), prevSrc - 10_000 * WAD);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevDst + out);
        assertEq(GemLike(DAI).balanceOf(address(swapper)), 0);
        assertEq(GemLike(USDC).balanceOf(address(swapper)), 0);
        assertEq(GemLike(DAI).balanceOf(address(uniV3Callee)), 0);
        assertEq(GemLike(USDC).balanceOf(address(uniV3Callee)), 0);
    }

    function testSwapAferHop() public {
        vm.prank(FACILITATOR); swapper.swap(USDC, DAI, 10_000 * 10**6, 9900 * WAD, address(uniV3Callee), USDC_DAI_PATH);
        (uint64  hop,,) = swapper.limits(USDC, DAI);
        vm.warp(block.timestamp + hop);

        vm.expectEmit(true, true, true, false);
        emit Swap(FACILITATOR, USDC, DAI, 10_000 * 10**6, 0);
        vm.prank(FACILITATOR); swapper.swap(USDC, DAI, 10_000 * 10**6, 9900 * WAD, address(uniV3Callee), USDC_DAI_PATH);
    }

    function testSwapTooSoon() public {
        vm.prank(FACILITATOR); swapper.swap(USDC, DAI, 10_000 * 10**6, 9900 * WAD, address(uniV3Callee), USDC_DAI_PATH);
        
        vm.expectRevert("Swapper/too-soon");
        vm.prank(FACILITATOR); swapper.swap(USDC, DAI, 10_000 * 10**6, 9900 * WAD, address(uniV3Callee), USDC_DAI_PATH);
    }

    function testSwapExceedingMax() public {
        (,, uint128 cap) = swapper.limits(USDC, DAI);
        uint256 amt = cap + 1;
        vm.expectRevert("Swapper/exceeds-max-amt");
        vm.prank(FACILITATOR); swapper.swap(USDC, DAI, amt, 0, address(uniV3Callee), USDC_DAI_PATH);
    }

    function testSwapReceivingTooLittle() public {
        CalleeMock callee = new CalleeMock();
        vm.expectRevert("Swapper/too-few-dst-received");
        vm.prank(FACILITATOR); swapper.swap(USDC, DAI, 100*10**6, 200*10**18, address(callee), USDC_DAI_PATH);
    }
}
