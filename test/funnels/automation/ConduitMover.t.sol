// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { ConduitMover } from "src/funnels/automation/ConduitMover.sol";
import { AllocatorRegistry } from "src/AllocatorRegistry.sol";
import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { AllocatorConduitMock } from "test/mocks/AllocatorConduitMock.sol";

interface GemLike {
    function balanceOf(address) external view returns (uint256);
}

contract ConduitMoverTest is DssTest {
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(address indexed from, address indexed to, address indexed gem, uint64 num, uint32 hop, uint128 lot);
    event Move(address indexed from, address indexed to, address indexed gem, uint128 lot);

    address         public buffer;
    address         public conduit1;
    address         public conduit2;
    ConduitMover    public mover;

    bytes32 constant ILK         = "aaa";
    address constant USDC        = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant FACILITATOR = address(0x1337);
    address constant KEEPER      = address(0xb0b);
    uint8   constant MOVER_ROLE  = uint8(1);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        buffer = address(new AllocatorBuffer());
        AllocatorRoles roles = new AllocatorRoles();
        AllocatorRegistry registry = new AllocatorRegistry();
        registry.file(ILK, "buffer", buffer);

        conduit1 = address(new AllocatorConduitMock(address(roles), address(registry)));
        conduit2 = address(new AllocatorConduitMock(address(roles), address(registry)));
        mover    = new ConduitMover(ILK, buffer);

        // Allow mover to perform ILK operations on the conduits
        roles.setIlkAdmin(ILK, address(this));
        roles.setRoleAction(ILK, MOVER_ROLE, conduit1, AllocatorConduitMock.deposit.selector, true);
        roles.setRoleAction(ILK, MOVER_ROLE, conduit1, AllocatorConduitMock.withdraw.selector, true);
        roles.setRoleAction(ILK, MOVER_ROLE, conduit2, AllocatorConduitMock.deposit.selector, true);
        roles.setUserRole(ILK, address(mover), MOVER_ROLE, true);

        // Allow conduits to transfer out funds out of the buffer
        AllocatorBuffer(buffer).approve(USDC, conduit1, type(uint256).max);
        AllocatorBuffer(buffer).approve(USDC, conduit2, type(uint256).max);

        // Give conduit1 some funds
        deal(USDC, buffer, 3_000 * 10**6, true);
        vm.prank(address(mover)); AllocatorConduitMock(conduit1).deposit(ILK, USDC, 3_000 * 10**6);

        // Set up keeper to move from conduit1 to conduit2
        mover.rely(FACILITATOR);
        vm.startPrank(FACILITATOR);
        mover.kiss(KEEPER);
        mover.setConfig(conduit1, conduit2, USDC, 10, 1 hours, uint128(1_000 * 10**6));
        vm.stopPrank();

        // Confirm initial parameters and amounts
        (uint64 num, uint32 hop, uint32 zzz, uint128 lot) = mover.configs(conduit1, conduit2, USDC);
        assertEq(num, 10);
        assertEq(hop, 1 hours);
        assertEq(zzz, 0);
        assertEq(lot, 1_000 * 10**6);
        assertEq(GemLike(USDC).balanceOf(buffer), 0);
        assertEq(GemLike(USDC).balanceOf(conduit1), 3_000 * 10**6);
        assertEq(GemLike(USDC).balanceOf(conduit2), 0);
    }

    function testConstructor() public {
        ConduitMover m = new ConduitMover("xyz", address(0xABC));
        assertEq(m.ilk(), "xyz");
        assertEq(m.buffer(), address(0xABC));
        assertEq(m.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(mover), "ConduitMover");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](3);
        authedMethods[0] = ConduitMover.kiss.selector;
        authedMethods[1] = ConduitMover.diss.selector;
        authedMethods[2] = ConduitMover.setConfig.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(mover), "ConduitMover/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testKissDiss() public {
        address testAddress = address(0x123);
        assertEq(mover.buds(testAddress), 0);

        vm.expectEmit(true, true, true, true);
        emit Kiss(testAddress);
        mover.kiss(testAddress);
        assertEq(mover.buds(testAddress), 1);

        vm.expectEmit(true, true, true, true);
        emit Diss(testAddress);
        mover.diss(testAddress);
        assertEq(mover.buds(testAddress), 0);
    }

    function testSetConfig() public {
        vm.expectEmit(true, true, true, true);
        emit SetConfig(address(0x123), address(0x456), address(0x789), uint64(23), uint32(360 seconds), uint96(314));
        mover.setConfig(address(0x123), address(0x456), address(0x789), uint64(23), uint32(360 seconds), uint96(314));

        (uint64 num, uint32 hop, uint32 zzz, uint128 lot) = mover.configs(address(0x123), address(0x456), address(0x789));
        assertEq(num, 23);
        assertEq(hop, 360);
        assertEq(zzz, 0);
        assertEq(lot, 314);
    }

    function testMoveByKeeper() public {
        vm.expectEmit(true, true, true, true);
        emit Move(conduit1, conduit2, USDC, 1_000 * 10**6);
        vm.prank(KEEPER); mover.move(conduit1, conduit2, USDC);

        assertEq(GemLike(USDC).balanceOf(conduit1), 2_000 * 10**6);
        assertEq(GemLike(USDC).balanceOf(conduit2), 1_000 * 10**6);
        assertEq(GemLike(USDC).balanceOf(buffer), 0);
        (uint64 num, uint32 hop, uint32 zzz, uint128 lot) = mover.configs(conduit1, conduit2, USDC);
        assertEq(num, 9);
        assertEq(hop, 1 hours);
        assertEq(zzz, block.timestamp);
        assertEq(lot, 1_000 * 10**6);

        vm.warp(block.timestamp + 1 hours - 1);
        vm.expectRevert("ConduitMover/too-soon");
        vm.prank(KEEPER); mover.move(conduit1, conduit2, USDC);

        vm.warp(block.timestamp + 1);
        vm.prank(KEEPER); mover.move(conduit1, conduit2, USDC);

        assertEq(GemLike(USDC).balanceOf(conduit1), 1_000 * 10**6);
        assertEq(GemLike(USDC).balanceOf(conduit2), 2_000 * 10**6);
        assertEq(GemLike(USDC).balanceOf(buffer), 0);
        (num, hop, zzz, lot) = mover.configs(conduit1, conduit2, USDC);
        assertEq(num, 8);
        assertEq(hop, 1 hours);
        assertEq(zzz, block.timestamp);
        assertEq(lot, 1_000 * 10**6);
    }

    function testMoveByKeeperToAndFromBuffer() public {
        // Set up keeper to move USDC between conduit1 and buffer
        vm.prank(FACILITATOR); mover.setConfig(conduit1, buffer, USDC, 10, 1 hours, uint128(1_000 * 10**6));
        vm.prank(FACILITATOR); mover.setConfig(buffer, conduit1, USDC, 10, 1 hours, uint128(1_000 * 10**6));
        assertEq(GemLike(USDC).balanceOf(conduit1), 3_000 * 10**6);
        assertEq(GemLike(USDC).balanceOf(buffer), 0);

        vm.expectEmit(true, true, true, true);
        emit Move(conduit1, buffer, USDC, 1_000 * 10**6);
        vm.prank(KEEPER); mover.move(conduit1, buffer, USDC);

        assertEq(GemLike(USDC).balanceOf(conduit1), 2_000 * 10**6);
        assertEq(GemLike(USDC).balanceOf(buffer), 1_000 * 10**6);
        (uint64 num, uint32 hop, uint32 zzz, uint128 lot) = mover.configs(conduit1, buffer, USDC);
        assertEq(num, 9);
        assertEq(hop, 1 hours);
        assertEq(zzz, block.timestamp);
        assertEq(lot, 1_000 * 10**6);

        vm.expectEmit(true, true, true, true);
        emit Move(buffer, conduit1, USDC, 1_000 * 10**6);
        vm.prank(KEEPER); mover.move(buffer, conduit1, USDC);

        assertEq(GemLike(USDC).balanceOf(conduit1), 3_000 * 10**6);
        assertEq(GemLike(USDC).balanceOf(buffer), 0);
        (num, hop, zzz, lot) = mover.configs(buffer, conduit1, USDC);
        assertEq(num, 9);
        assertEq(hop, 1 hours);
        assertEq(zzz, block.timestamp);
        assertEq(lot, 1_000 * 10**6);
    }

    function testMoveNonKeeper() public {
        assertEq(mover.buds(address(this)), 0);
        vm.expectRevert("ConduitMover/non-keeper");
        mover.move(conduit1, conduit2, USDC);
    }

    function testMoveExceedingNum() public {
        vm.expectRevert("ConduitMover/exceeds-num");
        vm.prank(KEEPER); mover.move(conduit1, conduit2, address(0x123));
    }
}
