// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { GemMock } from "test/mocks/GemMock.sol";

contract AllocatorBufferTest is DssTest {
    using stdStorage for StdStorage;

    bytes32         public ilk = "aaa";
    GemMock         public gem;
    AllocatorBuffer public buffer;

    event Approve(address indexed asset, address indexed spender, uint256 amount);
    event Deposit(bytes32 indexed ilk, address indexed asset, uint256 amount);
    event Withdraw(bytes32 indexed ilk, address indexed asset, address destination, uint256 amount);

    function setUp() public {
        gem    = new GemMock(1_000_000 * 10**18);
        buffer = new AllocatorBuffer(ilk);
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

    function testGetters() public {
        assertEq(buffer.maxDeposit(bytes32(0), address(0)), type(uint256).max);
        assertEq(buffer.maxWithdraw(bytes32(0), address(gem)), 0);
        gem.approve(address(buffer), 10);
        buffer.deposit(bytes32(0), address(gem), 10);
        assertEq(buffer.maxWithdraw(bytes32(0), address(gem)), 10);
    }

    function testApprove() public {
        assertEq(gem.allowance(address(buffer), address(0xBEEF)), 0);
        vm.expectEmit(true, true, true, true);
        emit Approve(address(gem), address(0xBEEF), 10);
        buffer.approve(address(gem), address(0xBEEF), 10);
        assertEq(gem.allowance(address(buffer), address(0xBEEF)), 10);
    }

    function testDepositWithdraw() public {
        assertEq(gem.balanceOf(address(this)),   gem.totalSupply());
        assertEq(gem.balanceOf(address(buffer)), 0);
        gem.approve(address(buffer), 10);
        vm.expectEmit(true, true, true, true);
        emit Deposit(buffer.ilk(), address(gem), 10);
        buffer.deposit(bytes32(0), address(gem), 10);
        assertEq(gem.balanceOf(address(this)),   gem.totalSupply() - 10);
        assertEq(gem.balanceOf(address(buffer)), 10);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(buffer.ilk(), address(gem), address(123), 4);
        assertEq(buffer.withdraw(bytes32(0), address(gem), address(123), 4), 4);
        assertEq(gem.balanceOf(address(buffer)), 6);
        assertEq(gem.balanceOf(address(123)),    4);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(buffer.ilk(), address(gem), address(123), 6);
        assertEq(buffer.withdraw(bytes32(0), address(gem), address(123), 7), 6);
        assertEq(gem.balanceOf(address(buffer)), 0);
        assertEq(gem.balanceOf(address(123)),    10);
    }
}
