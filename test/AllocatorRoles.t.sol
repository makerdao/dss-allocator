// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import "src/AllocatorRoles.sol";
import { AuthedMock } from "test/mocks/AuthedMock.sol";

contract AllocatorRolesTest is DssTest {
    AllocatorRoles roles;
    AuthedMock     authed;
    bytes32        ilk;

    event SetIlkAdmin(bytes32 indexed ilk, address user);
    event SetUserRole(bytes32 indexed ilk, address indexed who, uint8 indexed role, bool enabled);
    event SetRoleAction(bytes32 indexed ilk, uint8 indexed role, address indexed target, bytes4 sig, bool enabled);

    function setUp() public {
        ilk = "aaa";
        roles = new AllocatorRoles();
        authed = new AuthedMock(address(roles), ilk);
    }

    function testAuth() public {
        checkAuth(address(roles), "AllocatorRoles");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](1);
        authedMethods[0] = roles.setIlkAdmin.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(roles), "AllocatorRoles/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testBasics() public {
        uint8 admin_role = 0;
        uint8 mod_role = 1;
        uint8 user_role = 2;
        uint8 max_role = 255;

        assertTrue(!roles.hasUserRole(ilk, address(this), admin_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), mod_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), user_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), max_role));
        assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000000"), roles.userRoles(ilk, address(this)));

        vm.expectRevert("AllocatorRoles/ilk-not-authorized");
        roles.setUserRole(ilk, address(this), admin_role, true);

        vm.expectEmit(true, true, true, true);
        emit SetIlkAdmin(ilk, address(this));
        roles.setIlkAdmin(ilk, address(this));
        vm.expectEmit(true, true, true, true);
        emit SetUserRole(ilk, address(this), admin_role, true);
        roles.setUserRole(ilk, address(this), admin_role, true);

        assertTrue( roles.hasUserRole(ilk, address(this), admin_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), mod_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), user_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), max_role));
        assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000001"), roles.userRoles(ilk, address(this)));

        assertTrue(!roles.canCall(ilk, address(this), address(authed), bytes4(keccak256("exec()"))));
        vm.expectRevert("AuthedMock/not-authorized");
        authed.exec();

        vm.expectEmit(true, true, true, true);
        emit SetRoleAction(ilk, admin_role, address(authed), bytes4(keccak256("exec()")), true);
        roles.setRoleAction(ilk, admin_role, address(authed), bytes4(keccak256("exec()")), true);

        assertTrue(roles.canCall(ilk, address(this), address(authed), bytes4(keccak256("exec()"))));
        authed.exec();
        assertTrue(authed.flag());

        vm.expectEmit(true, true, true, true);
        emit SetRoleAction(ilk, admin_role, address(authed), bytes4(keccak256("exec()")), false);
        roles.setRoleAction(ilk, admin_role, address(authed), bytes4(keccak256("exec()")), false);
        assertTrue(!roles.canCall(ilk, address(this), address(authed), bytes4(keccak256("exec()"))));
        vm.expectRevert("AuthedMock/not-authorized");
        authed.exec();

        vm.expectEmit(true, true, true, true);
        emit SetUserRole(ilk, address(this), mod_role, true);
        roles.setUserRole(ilk, address(this), mod_role, true);

        assertTrue( roles.hasUserRole(ilk, address(this), admin_role));
        assertTrue( roles.hasUserRole(ilk, address(this), mod_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), user_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), max_role));
        assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000003"), roles.userRoles(ilk, address(this)));

        vm.expectEmit(true, true, true, true);
        emit SetUserRole(ilk, address(this), user_role, true);
        roles.setUserRole(ilk, address(this), user_role, true);

        assertTrue( roles.hasUserRole(ilk, address(this), admin_role));
        assertTrue( roles.hasUserRole(ilk, address(this), mod_role));
        assertTrue( roles.hasUserRole(ilk, address(this), user_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), max_role));
        assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000007"), roles.userRoles(ilk, address(this)));

        vm.expectEmit(true, true, true, true);
        emit SetUserRole(ilk, address(this), mod_role, false);
        roles.setUserRole(ilk, address(this), mod_role, false);

        assertTrue( roles.hasUserRole(ilk, address(this), admin_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), mod_role));
        assertTrue( roles.hasUserRole(ilk, address(this), user_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), max_role));
        assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000005"), roles.userRoles(ilk, address(this)));

        vm.expectEmit(true, true, true, true);
        emit SetUserRole(ilk, address(this), max_role, true);
        roles.setUserRole(ilk, address(this), max_role, true);

        assertTrue( roles.hasUserRole(ilk, address(this), admin_role));
        assertTrue(!roles.hasUserRole(ilk, address(this), mod_role));
        assertTrue( roles.hasUserRole(ilk, address(this), user_role));
        assertTrue( roles.hasUserRole(ilk, address(this), max_role));
        assertEq32(bytes32(hex"8000000000000000000000000000000000000000000000000000000000000005"), roles.userRoles(ilk, address(this)));

        vm.expectEmit(true, true, true, true);
        emit SetRoleAction(ilk, max_role, address(authed), bytes4(keccak256("exec()")), true);
        roles.setRoleAction(ilk, max_role, address(authed), bytes4(keccak256("exec()")), true);
        assertTrue(roles.canCall(ilk, address(this), address(authed), bytes4(keccak256("exec()"))));
        authed.exec();
    }
}
