// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { AllocatorBuffer } from "../AllocatorBuffer.sol";
import { GemMock } from "./mocks/GemMock.sol";

contract AllocatorBufferTest is DssTest {
    using stdStorage for StdStorage;

    GemMock         public gem;
    AllocatorBuffer public buffer;

    function setUp() public {
        gem    = new GemMock(1_000_000 * 10**18);
        buffer = new AllocatorBuffer();
    }

    function testAuth() public {
        checkAuth(address(buffer), "AllocatorBuffer");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](1);
        authedMethods[0] = buffer.approve.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(buffer), "AllocatorBuffer/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testApprove() public {
        assertEq(gem.allowance(address(buffer), address(0xBEEF)), 0);
        buffer.approve(address(gem), address(0xBEEF), 10);
        assertEq(gem.allowance(address(buffer), address(0xBEEF)), 10);
    }

    function testDeposit() public {
        assertEq(gem.balanceOf(address(this)),   gem.totalSupply());
        assertEq(gem.balanceOf(address(buffer)), 0);
        gem.approve(address(buffer), 10);
        buffer.deposit(address(gem), 10, address(0));
        assertEq(gem.balanceOf(address(this)),   gem.totalSupply() - 10);
        assertEq(gem.balanceOf(address(buffer)), 10);
    }
}
