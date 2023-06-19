// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { WhitelistedRouter } from "src/WhitelistedRouter.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { GemMock } from "./mocks/GemMock.sol";

interface BalanceLike {
    function balanceOf(address) external view returns (uint256);
}

interface GemLikeLike {
    function approve(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

contract WhitelistedRouterTest is DssTest {
    WhitelistedRouter public router;
    address public box1;
    address public box2;
    address public USDC;
    address public USDT;

    address constant FACILITATOR = address(0xb0b);
    address constant SUBDAO_PROXY = address(0xDA0);

    function setUp() public {
        router = new WhitelistedRouter();
        box1 = address(new AllocatorBuffer());
        box2 = address(new AllocatorBuffer());
        USDC = address(new GemMock(1_000_000 ether));
        USDT = address(new GemMock(1_000_000 ether));
        AllocatorBuffer(box1).approve(USDC, address(router), type(uint256).max);
        AllocatorBuffer(box2).approve(USDC, address(router), type(uint256).max);
        AllocatorBuffer(box1).approve(USDT, address(router), type(uint256).max);
        AllocatorBuffer(box2).approve(USDT, address(router), type(uint256).max);
        router.file("box", box1, 1);
        router.file("box", box2, 1);
        router.file("owner", SUBDAO_PROXY);
        router.kiss(FACILITATOR);
    }

    function _checkMove(address gem, uint256 amt) internal {
        deal(gem, box1, amt, true);
        assertEq(BalanceLike(gem).balanceOf(box1), amt);
        assertEq(BalanceLike(gem).balanceOf(box2), 0);
        vm.startPrank(FACILITATOR); 
        
        router.move(gem, box1, box2, amt);

        assertEq(BalanceLike(gem).balanceOf(box1), 0);
        assertEq(BalanceLike(gem).balanceOf(box2), amt);

        router.move(gem, box2, box1, amt);

        assertEq(BalanceLike(gem).balanceOf(box1), amt);
        assertEq(BalanceLike(gem).balanceOf(box2), 0);
        vm.stopPrank();
    }

    function testMoveUSDC() public {
        _checkMove(USDC, 1000 ether);
    }
    function testMoveUSDT() public {
        _checkMove(USDT, 1000 ether);
    }
}
