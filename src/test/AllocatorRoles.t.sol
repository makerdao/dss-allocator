// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import "../AllocatorRoles.sol";
import { AuthedMock } from "./mocks/AuthedMock.sol";

contract AllocatorRolesTest is DssTest {
    AllocatorRoles roles;
    AuthedMock     authed;

    function setUp() public {
        roles = new AllocatorRoles();
        authed = new AuthedMock(address(roles));
    }

    function testAuth() public {
        checkAuth(address(roles), "AllocatorRoles");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](3);
        authedMethods[0] = roles.setUserRole.selector;
        authedMethods[1] = roles.setPublicAction.selector;
        authedMethods[2] = roles.setRoleAction.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(roles), "AllocatorRoles/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testBasics() public {
        uint8 admin_role = 0;
        uint8 mod_role = 1;
        uint8 user_role = 2;
        uint8 max_role = 255;

        assertTrue(!roles.hasUserRole(address(this), admin_role));
        assertTrue(!roles.hasUserRole(address(this), mod_role));
        assertTrue(!roles.hasUserRole(address(this), user_role));
        assertTrue(!roles.hasUserRole(address(this), max_role));
        assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000000"), roles.userRoles(address(this)));

        roles.setUserRole(address(this), admin_role, true);

        assertTrue( roles.hasUserRole(address(this), admin_role));
        assertTrue(!roles.hasUserRole(address(this), mod_role));
        assertTrue(!roles.hasUserRole(address(this), user_role));
        assertTrue(!roles.hasUserRole(address(this), max_role));
        assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000001"), roles.userRoles(address(this)));

        assertTrue(!roles.canCall(address(this), address(authed), bytes4(keccak256("exec()"))));
        vm.expectRevert("AuthedMock/not-authorized");
        authed.exec();

        roles.setRoleAction(admin_role, address(authed), bytes4(keccak256("exec()")), true);

        assertTrue(roles.canCall(address(this), address(authed), bytes4(keccak256("exec()"))));
        authed.exec();
        assertTrue(authed.flag());

        roles.setRoleAction(admin_role, address(authed), bytes4(keccak256("exec()")), false);
        assertTrue(!roles.canCall(address(this), address(authed), bytes4(keccak256("exec()"))));
        vm.expectRevert("AuthedMock/not-authorized");
        authed.exec();

        roles.setUserRole(address(this), mod_role, true);

        assertTrue( roles.hasUserRole(address(this), admin_role));
        assertTrue( roles.hasUserRole(address(this), mod_role));
        assertTrue(!roles.hasUserRole(address(this), user_role));
        assertTrue(!roles.hasUserRole(address(this), max_role));
        assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000003"), roles.userRoles(address(this)));

        roles.setUserRole(address(this), user_role, true);

        assertTrue( roles.hasUserRole(address(this), admin_role));
        assertTrue( roles.hasUserRole(address(this), mod_role));
        assertTrue( roles.hasUserRole(address(this), user_role));
        assertTrue(!roles.hasUserRole(address(this), max_role));
        assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000007"), roles.userRoles(address(this)));

        roles.setUserRole(address(this), mod_role, false);

        assertTrue( roles.hasUserRole(address(this), admin_role));
        assertTrue(!roles.hasUserRole(address(this), mod_role));
        assertTrue( roles.hasUserRole(address(this), user_role));
        assertTrue(!roles.hasUserRole(address(this), max_role));
        assertEq32(bytes32(hex"0000000000000000000000000000000000000000000000000000000000000005"), roles.userRoles(address(this)));

        roles.setUserRole(address(this), max_role, true);

        assertTrue( roles.hasUserRole(address(this), admin_role));
        assertTrue(!roles.hasUserRole(address(this), mod_role));
        assertTrue( roles.hasUserRole(address(this), user_role));
        assertTrue( roles.hasUserRole(address(this), max_role));
        assertEq32(bytes32(hex"8000000000000000000000000000000000000000000000000000000000000005"), roles.userRoles(address(this)));

        roles.setRoleAction(max_role, address(authed), bytes4(keccak256("exec()")), true);
        assertTrue(roles.canCall(address(this), address(authed), bytes4(keccak256("exec()"))));
        authed.exec();
    }

    function testPublicActions() public {
        assertEq(roles.publicActions(address(authed), bytes4(keccak256("exec()"))), 0);
        assertTrue(!roles.canCall(address(this), address(authed), bytes4(keccak256("exec()"))));
        vm.expectRevert("AuthedMock/not-authorized");
        authed.exec();

        roles.setPublicAction(address(authed), bytes4(keccak256("exec()")), true);
        assertEq(roles.publicActions(address(authed), bytes4(keccak256("exec()"))), 1);
        assertTrue(roles.canCall(address(this), address(authed), bytes4(keccak256("exec()"))));
        authed.exec();

        roles.setPublicAction(address(authed), bytes4(keccak256("exec()")), false);
        assertEq(roles.publicActions(address(authed), bytes4(keccak256("exec()"))), 0);
        assertTrue(!roles.canCall(address(this), address(authed), bytes4(keccak256("exec()"))));
        vm.expectRevert("AuthedMock/not-authorized");
        authed.exec();
    }
}
