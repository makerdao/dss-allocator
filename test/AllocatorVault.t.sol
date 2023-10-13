// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { AllocatorVault } from "src/AllocatorVault.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { RolesMock } from "test/mocks/RolesMock.sol";
import { VatMock } from "test/mocks/VatMock.sol";
import { JugMock } from "test/mocks/JugMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { NstJoinMock } from "test/mocks/NstJoinMock.sol";

contract AllocatorVaultTest is DssTest {
    using stdStorage for StdStorage;

    VatMock         public vat;
    JugMock         public jug;
    GemMock         public nst;
    NstJoinMock     public nstJoin;
    AllocatorBuffer public buffer;
    RolesMock       public roles;
    AllocatorVault  public vault;
    bytes32         public ilk;

    event Init();
    event Draw(address indexed sender, uint256 wad);
    event Wipe(address indexed sender, uint256 wad);

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // Note: _divup(0,0) will return 0 differing from natural solidity division
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

    function setUp() public {
        ilk     = "TEST-ILK";
        vat     = new VatMock();
        jug     = new JugMock(vat);
        nst     = new GemMock(0);
        nstJoin = new NstJoinMock(vat, nst);
        buffer  = new AllocatorBuffer();
        roles   = new RolesMock();
        vault   = new AllocatorVault(address(roles), address(buffer), ilk, address(nstJoin));
        buffer.approve(address(nst), address(vault), type(uint256).max);

        vat.slip(ilk, address(vault), int256(1_000_000 * WAD));
        vat.grab(ilk, address(vault), address(vault), address(0), int256(1_000_000 * WAD), 0);

        // Add some existing DAI assigned to nstJoin to avoid a particular error
        stdstore.target(address(vat)).sig("dai(address)").with_key(address(nstJoin)).depth(0).checked_write(100_000 * RAD);
    }

    function testAuth() public {
        checkAuth(address(vault), "AllocatorVault");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](2);
        authedMethods[0] = vault.draw.selector;
        authedMethods[1] = vault.wipe.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(vault), "AllocatorVault/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testFile() public {
        checkFileAddress(address(vault), "AllocatorVault", ["jug"]);
    }

    function testRoles() public {
        vm.startPrank(address(0xBEEF));
        vm.expectRevert("AllocatorVault/not-authorized");
        vault.file("jug", address(0));
        roles.setOk(true);
        vault.file("jug", address(0));
    }

    function testDrawWipe() public {
        vault.file("jug", address(jug));
        (, uint256 art) = vat.urns(ilk, address(buffer));
        assertEq(art, 0);
        vm.expectEmit(true, true, true, true);
        emit Draw(address(this), 50 * 10**18);
        vault.draw(50 * 10**18);
        (, art) = vat.urns(ilk, address(vault));
        assertEq(art, 50 * 10**18);
        assertEq(vat.rate(), 10**27);
        assertEq(nst.balanceOf(address(buffer)), 50 * 10**18);
        vm.warp(block.timestamp + 1);
        vm.expectEmit(true, true, true, true);
        emit Draw(address(this), 50 * 10**18);
        vault.draw(50 * 10**18);
        (, art) = vat.urns(ilk, address(vault));
        uint256 expectedArt = 50 * 10**18 + _divup(50 * 10**18 * 1000, 1001);
        assertEq(art, expectedArt);
        assertEq(vat.rate(), 1001 * 10**27 / 1000);
        assertEq(nst.balanceOf(address(buffer)), 100 * 10**18);
        assertGt(art * vat.rate(), 100.05 * 10**45);
        assertLt(art * vat.rate(), 100.06 * 10**45);
        vm.expectRevert("Gem/insufficient-balance");
        vault.wipe(100.06 * 10**18);
        deal(address(nst), address(buffer), 100.06 * 10**18, true);
        assertEq(nst.balanceOf(address(buffer)), 100.06 * 10**18);
        vm.expectRevert();
        vault.wipe(100.06 * 10**18); // It will try to wipe more art than existing, then reverts
        vm.expectEmit(true, true, true, true);
        emit Wipe(address(this), 100.05 * 10**18);
        vault.wipe(100.05 * 10**18);
        assertEq(nst.balanceOf(address(buffer)), 0.01 * 10**18);
        (, art) = vat.urns(ilk, address(vault));
        assertEq(art, 1); // Dust which is impossible to wipe
    }
}
