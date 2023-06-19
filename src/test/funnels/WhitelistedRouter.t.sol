// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "../../funnels/WhitelistedRouter.sol";
import "../../AllocatorBuffer.sol";
import "dss-test/DssTest.sol";

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

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant FACILITATOR = address(0xb0b);
    address constant SUBDAO_PROXY = address(0xDA0);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        router = new WhitelistedRouter();
        box1 = address(new AllocatorBuffer());
        box2 = address(new AllocatorBuffer());
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
