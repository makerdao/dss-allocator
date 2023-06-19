// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { WhitelistedRouter } from "src/WhitelistedRouter.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { GemMock } from "./mocks/GemMock.sol";
import { RolesMock } from "./mocks/RolesMock.sol";

interface BalanceLike {
    function balanceOf(address) external view returns (uint256);
}

interface GemLikeLike {
    function approve(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

contract WhitelistedRouterTest is DssTest {
    bytes32           public ilk;
    RolesMock         public roles;
    WhitelistedRouter public router;
    address           public box1;
    address           public box2;
    address           public USDC;
    address           public USDT;

    address constant FACILITATOR = address(0xb0b);

    function setUp() public {
        ilk    = "TEST-ILK";
        roles  = new RolesMock();
        router = new WhitelistedRouter(address(roles), ilk);
        box1 = address(new AllocatorBuffer());
        box2 = address(new AllocatorBuffer());
        USDC = address(new GemMock(0));
        USDT = address(new GemMock(0));
        AllocatorBuffer(box1).rely(address(router));
        AllocatorBuffer(box2).rely(address(router));
        router.file("box", box1, 1);
        router.file("box", box2, 1);
    }

    function _checkMove(bool ward, address gem, uint256 amt) internal {
        if (ward) {
            router.rely(FACILITATOR);
        } else {
            roles.setOk(true);
        }

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

    function testMoveUSDCWard() public {
        _checkMove(true, USDC, 1000 ether);
    }

    function testMoveUSDCRoles() public {
        _checkMove(false, USDC, 1000 ether);
    }

    function testMoveUSDTWard() public {
        _checkMove(true, USDT, 1000 ether);
    }

    function testMoveUSDTRoles() public {
        _checkMove(false, USDT, 1000 ether);
    }
}
