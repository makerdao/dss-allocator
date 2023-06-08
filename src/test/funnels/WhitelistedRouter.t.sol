// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "../../funnels/WhitelistedRouter.sol";
import "../../funnels/Escrow.sol";
import "dss-test/DssTest.sol";

interface BalanceLike {
    function balanceOf(address) external view returns (uint256);
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
        router = new WhitelistedRouter();
        box1 = address(new Escrow());
        box2 = address(new Escrow());
        Escrow(box1).approve(USDC, address(router), type(uint256).max);
        Escrow(box2).approve(USDC, address(router), type(uint256).max);
        Escrow(box1).approve(USDT, address(router), type(uint256).max);
        Escrow(box2).approve(USDT, address(router), type(uint256).max);
        router.file("box", box1, 1);
        router.file("box", box2, 1);
        router.file("owner", SUBDAO_PROXY);
        router.kiss(FACILITATOR);
    }

    function _checkTransferFrom(address gem, uint256 amt) internal {
        deal(gem, box1, amt, true);
        assertEq(BalanceLike(gem).balanceOf(box1), amt);
        assertEq(BalanceLike(gem).balanceOf(box2), 0);
        vm.startPrank(FACILITATOR); 
        
        router.transferFrom(gem, box1, box2, amt);

        assertEq(BalanceLike(gem).balanceOf(box1), 0);
        assertEq(BalanceLike(gem).balanceOf(box2), amt);

        router.transferFrom(gem, box2, box1, amt);

        assertEq(BalanceLike(gem).balanceOf(box1), amt);
        assertEq(BalanceLike(gem).balanceOf(box2), 0);
        vm.stopPrank();
    }

    function testTransferFromUSDC() public {
        _checkTransferFrom(USDC, 1000 ether);
    }
    function testTransferFromUSDT() public {
        _checkTransferFrom(USDT, 1000 ether);
    }
}
