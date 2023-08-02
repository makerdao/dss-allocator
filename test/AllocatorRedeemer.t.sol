// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { AllocatorRedeemer } from "src/AllocatorRedeemer.sol";
import { AllocatorVault } from "src/AllocatorVault.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { RolesMock } from "test/mocks/RolesMock.sol";
import { VatMock } from "test/mocks/VatMock.sol";
import { JugMock } from "test/mocks/JugMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { GemJoinMock } from "test/mocks/GemJoinMock.sol";
import { NstJoinMock } from "test/mocks/NstJoinMock.sol";

contract AllocatorRedeemerTest is DssTest {
    using stdStorage for StdStorage;

    VatMock           public vat;
    JugMock           public jug;
    GemMock           public gem;
    GemJoinMock       public gemJoin;
    GemMock           public nst;
    NstJoinMock       public nstJoin;
    AllocatorBuffer   public buffer;
    RolesMock         public roles;
    AllocatorVault    public vault;
    bytes32           public ilk;
    AllocatorRedeemer public redeemer;
    GemMock           public usdc;

    function setUp() public {
        ilk      = "TEST-ILK";
        vat      = new VatMock();
        jug      = new JugMock(vat);
        gem      = new GemMock(1_000_000 * 10**18);
        gemJoin  = new GemJoinMock(vat, ilk, gem);
        nst      = new GemMock(0);
        nstJoin  = new NstJoinMock(vat, nst);
        buffer   = new AllocatorBuffer();
        roles    = new RolesMock();
        vault    = new AllocatorVault(address(roles), address(buffer), address(vat), address(gemJoin), address(nstJoin));
        buffer.approve(address(nst), address(vault), type(uint256).max);
        gem.transfer(address(vault), 1_000_000 * 10**18);
        redeemer = new AllocatorRedeemer(address(vat), address(vault), address(buffer));
        buffer.rely(address(redeemer));
        usdc     = new GemMock(100_000_000 * 10**6);
        usdc.transfer(address(buffer), 100_000_000 * 10**6);
    }

    function testPull() public {
        vm.expectRevert("AllocatorRedeemer/system-live");
        redeemer.pull(address(usdc));

        assertEq(vat.live(), 1);
        vat.cage();
        assertEq(vat.live(), 0);

        assertEq(usdc.balanceOf(address(buffer)), 100_000_000 * 10**6);
        assertEq(usdc.balanceOf(address(redeemer)), 0);
        redeemer.pull(address(usdc));
        assertEq(usdc.balanceOf(address(buffer)), 0);
        assertEq(usdc.balanceOf(address(redeemer)), 100_000_000 * 10**6);
    }
}
