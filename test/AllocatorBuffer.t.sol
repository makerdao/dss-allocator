// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { GemMock } from "test/mocks/GemMock.sol";

contract AllocatorBufferTest is DssTest {
    using stdStorage for StdStorage;

    GemMock         public gem;
    AllocatorBuffer public buffer;

    event Approve(address indexed asset, address indexed spender, uint256 amount);

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

    function testTransferApproveWithdraw() public {
        assertEq(gem.balanceOf(address(this)),   gem.totalSupply());
        assertEq(gem.balanceOf(address(buffer)), 0);
        gem.transfer(address(buffer), 10);
        assertEq(gem.balanceOf(address(this)),   gem.totalSupply() - 10);
        assertEq(gem.balanceOf(address(buffer)), 10);
        assertEq(gem.allowance(address(buffer), address(this)), 0);
        vm.expectEmit(true, true, true, true);
        emit Approve(address(gem), address(this), 4);
        buffer.approve(address(gem), address(this), 4);
        assertEq(gem.allowance(address(buffer), address(this)), 4);
        gem.transferFrom(address(buffer), address(123), 4);
        assertEq(gem.balanceOf(address(buffer)), 6);
        assertEq(gem.balanceOf(address(123)),    4);
    }
}
