// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { VaultMinter } from "src/funnels/automation/VaultMinter.sol";
import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorVault } from "src/AllocatorVault.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { VatMock } from "test/mocks/VatMock.sol";
import { JugMock } from "test/mocks/JugMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { UsdsJoinMock } from "test/mocks/UsdsJoinMock.sol";

contract VaultMinterTest is DssTest {
    using stdStorage for StdStorage;

    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(int64 num, uint32 hop, uint128 lot);
    event Draw(uint128 lot);
    event Wipe(uint128 lot);

    VatMock         public vat;
    JugMock         public jug;
    GemMock         public usds;
    UsdsJoinMock    public usdsJoin;
    AllocatorBuffer public buffer;
    AllocatorRoles  public roles;
    AllocatorVault  public vault;
    VaultMinter     public minter;

    bytes32 constant ILK         = "aaa";
    address constant FACILITATOR = address(0x1337);
    address constant KEEPER      = address(0xb0b);
    uint8   constant MINTER_ROLE  = uint8(1);

    function setUp() public {
        vat      = new VatMock();
        jug      = new JugMock(vat);
        usds     = new GemMock(0);
        usdsJoin = new UsdsJoinMock(vat, usds);
        buffer   = new AllocatorBuffer();
        roles    = new AllocatorRoles();
        vault    = new AllocatorVault(address(roles), address(buffer), ILK, address(usdsJoin));
        vault.file("jug", address(jug));
        buffer.approve(address(usds), address(vault), type(uint256).max);

        vat.slip(ILK, address(vault), int256(1_000_000 * WAD));
        vat.grab(ILK, address(vault), address(vault), address(0), int256(1_000_000 * WAD), 0);

        minter = new VaultMinter(address(vault));

        // Allow minter to perform operations in the vault
        roles.setIlkAdmin(ILK, address(this));
        roles.setRoleAction(ILK, MINTER_ROLE, address(vault), AllocatorVault.draw.selector, true);
        roles.setRoleAction(ILK, MINTER_ROLE, address(vault), AllocatorVault.wipe.selector, true);
        roles.setUserRole(ILK, address(minter), MINTER_ROLE, true);

        // Set up keeper to mint and burn
        minter.rely(FACILITATOR);
        vm.prank(FACILITATOR); minter.kiss(KEEPER);

        vm.warp(1 hours);
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        VaultMinter m = new VaultMinter(address(0xABC));
        assertEq(m.vault(), address(0xABC));
        assertEq(m.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(minter), "VaultMinter");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](3);
        authedMethods[0] = VaultMinter.kiss.selector;
        authedMethods[1] = VaultMinter.diss.selector;
        authedMethods[2] = VaultMinter.setConfig.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(minter), "VaultMinter/not-authorized", authedMethods);
        vm.stopPrank();

        bytes4[] memory keeperMethods = new bytes4[](2);
        keeperMethods[0] = VaultMinter.draw.selector;
        keeperMethods[1] = VaultMinter.wipe.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(minter), "VaultMinter/non-keeper", keeperMethods);
        vm.stopPrank();
    }

    function testKissDiss() public {
        address testAddress = address(0x123);
        assertEq(minter.buds(testAddress), 0);

        vm.expectEmit(true, true, true, true);
        emit Kiss(testAddress);
        minter.kiss(testAddress);
        assertEq(minter.buds(testAddress), 1);

        vm.expectEmit(true, true, true, true);
        emit Diss(testAddress);
        minter.diss(testAddress);
        assertEq(minter.buds(testAddress), 0);
    }

    function testSetConfig() public {
        vm.expectEmit(true, true, true, true);
        emit SetConfig(int64(23), uint32(360 seconds), uint128(314));
        minter.setConfig(int64(23), uint32(360 seconds), uint128(314));

        (int64 num, uint32 hop, uint32 zzz, uint128 lot) = minter.config();
        assertEq(num, 23);
        assertEq(hop, 360);
        assertEq(zzz, 0);
        assertEq(lot, 314);

        vm.expectEmit(true, true, true, true);
        emit SetConfig(-int64(10), uint32(180 seconds), uint128(411));
        minter.setConfig(-int64(10), uint32(180 seconds), uint128(411));

        (num, hop, zzz, lot) = minter.config();
        assertEq(num, -int64(10));
        assertEq(hop, 180);
        assertEq(zzz, 0);
        assertEq(lot, 411);
    }

    function testDrawWipeByKeeper() public {
        minter.setConfig(int64(10), uint32(1 hours), uint128(1_000 * WAD));

        assertEq(usds.balanceOf(address(buffer)), 0);
        (int64 num, uint32 hop, uint32 zzz, uint128 lot) = minter.config();
        assertEq(num, 10);
        assertEq(hop, 1 hours);
        assertEq(zzz, 0);
        assertEq(lot, 1_000 * WAD);

        vm.expectEmit(true, true, true, true);
        emit Draw(uint128(1_000 * WAD));
        vm.prank(KEEPER); minter.draw();

        assertEq(usds.balanceOf(address(buffer)), 1_000 * WAD);
        (num, hop, zzz, lot) = minter.config();
        assertEq(num, 9);
        assertEq(hop, 1 hours);
        assertEq(zzz, block.timestamp);
        assertEq(lot, 1_000 * WAD);

        vm.warp(block.timestamp + 1 hours - 1);
        vm.expectRevert("VaultMinter/too-soon");
        vm.prank(KEEPER); minter.draw();

        vm.warp(block.timestamp + 1);
        vm.prank(KEEPER); minter.draw();

        assertEq(usds.balanceOf(address(buffer)), 2_000 * WAD);
        (num, hop, zzz, lot) = minter.config();
        assertEq(num, 8);
        assertEq(hop, 1 hours);
        assertEq(zzz, block.timestamp);
        assertEq(lot, 1_000 * WAD);

        minter.setConfig(-int64(10), uint32(1 hours), uint128(100 * WAD));

        (num, hop, zzz, lot) = minter.config();
        assertEq(num, -10);
        assertEq(hop, 1 hours);
        assertEq(zzz, 0);
        assertEq(lot, 100 * WAD);

        vm.expectEmit(true, true, true, true);
        emit Wipe(uint128(100 * WAD));
        vm.prank(KEEPER); minter.wipe();

        assertEq(usds.balanceOf(address(buffer)), 1_900 * WAD);
        (num, hop, zzz, lot) = minter.config();
        assertEq(num, -9);
        assertEq(hop, 1 hours);
        assertEq(zzz, block.timestamp);
        assertEq(lot, 100 * WAD);

        vm.warp(block.timestamp + 1 hours - 1);
        vm.expectRevert("VaultMinter/too-soon");
        vm.prank(KEEPER); minter.wipe();

        vm.warp(block.timestamp + 1);
        vm.prank(KEEPER); minter.wipe();

        assertEq(usds.balanceOf(address(buffer)), 1_800 * WAD);
        (num, hop, zzz, lot) = minter.config();
        assertEq(num, -8);
        assertEq(hop, 1 hours);
        assertEq(zzz, block.timestamp);
        assertEq(lot, 100 * WAD);
    }

    function testMintBurnExceedingNum() public {
        vm.expectRevert("VaultMinter/exceeds-num");
        vm.prank(KEEPER); minter.draw();
        vm.expectRevert("VaultMinter/exceeds-num");
        vm.prank(KEEPER); minter.wipe();
    }
}
