// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { AllocatorRegistry } from "src/AllocatorRegistry.sol";

contract AllocatorRegistryTest is DssTest {
    AllocatorRegistry public registry;

    event File(bytes32 indexed ilk, bytes32 indexed what, address data);

    function setUp() public {
        registry = new AllocatorRegistry();
    }

    function testAuth() public {
        checkAuth(address(registry), "AllocatorRegistry");
    }

    function testFileIlkAddress() public {
        // First check an invalid value
        vm.expectRevert("AllocatorRegistry/file-unrecognized-param");
        registry.file("any", "an invalid value", address(123));

        // Update value
        vm.expectEmit(true, true, true, true);
        emit File("any", "buffer", address(123));
        registry.file("any", "buffer", address(123));
        assertEq(registry.buffers("any"), address(123));

        // Finally check that file is authed
        registry.deny(address(this));
        vm.expectRevert("AllocatorRegistry/not-authorized");
        registry.file("any", "data", address(123));
    }
}
