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
    address           public user1 = address(0x1);
    address           public user2 = address(0x2);
    address           public user3 = address(0x3);
    address           public user4 = address(0x4);

    event Pull(address indexed asset, uint256 amt);
    event Pack(address indexed sender, uint256 wad);
    event Cash(address indexed asset, address indexed sender, uint256 wad);

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
        usdc     = new GemMock(20_000_000 * 10**6);
    }

    function testCage() public {
        vault.init();
        vault.file("jug", address(jug));
        assertEq(vault.line(), 20_000_000 * 10**18);
        vault.draw(20_000_000 * 10**18);
        (, uint256 art) = vat.urns(ilk, address(vault));
        assertEq(art, 20_000_000 * 10**18);

        // Simulate swap NST -> USDC
        buffer.approve(address(nst), address(this), 10_000_000 * 10**18);
        nst.transferFrom(address(buffer), address(this), 10_000_000 * 10**18);
        usdc.transfer(address(buffer), 10_000_000 * 10**6);
        assertEq(nst.balanceOf(address(buffer)),  10_000_000 * 10**18);
        assertEq(usdc.balanceOf(address(buffer)), 10_000_000 * 10**6);

        vm.expectRevert("AllocatorRedeemer/system-live");
        redeemer.pull(address(usdc));

        assertEq(vat.live(), 1);
        vat.cage();
        assertEq(vat.live(), 0);

        assertEq(nst.balanceOf(address(buffer)), 10_000_000 * 10**18);
        assertEq(nst.balanceOf(address(redeemer)), 0);
        vm.expectEmit(true, true, true, true);
        emit Pull(address(nst), 10_000_000 * 10**18);
        redeemer.pull(address(nst));
        assertEq(nst.balanceOf(address(buffer)), 0);
        assertEq(nst.balanceOf(address(redeemer)), 10_000_000 * 10**18);

        assertEq(usdc.balanceOf(address(buffer)), 10_000_000 * 10**6);
        assertEq(usdc.balanceOf(address(redeemer)), 0);
        vm.expectEmit(true, true, true, true);
        emit Pull(address(usdc), 10_000_000 * 10**6);
        redeemer.pull(address(usdc));
        assertEq(usdc.balanceOf(address(buffer)), 0);
        assertEq(usdc.balanceOf(address(redeemer)), 10_000_000 * 10**6);

        // Simulate skim (only 40% of the totalSupply of the token)
        vat.grab(ilk, address(vault), address(this), address(0), -400_000 * 10**18, -int256(art));

        gemJoin.exit(user1, 100_000 * 10**18);
        gemJoin.exit(user2, 100_000 * 10**18);
        gemJoin.exit(user3, 100_000 * 10**18);
        gemJoin.exit(user4, 100_000 * 10**18);

        vm.prank(user1); gem.approve(address(redeemer), type(uint256).max);
        vm.prank(user2); gem.approve(address(redeemer), type(uint256).max);
        vm.prank(user3); gem.approve(address(redeemer), type(uint256).max);
        vm.prank(user4); gem.approve(address(redeemer), type(uint256).max);

        vm.expectRevert("AllocatorRedeemer/wad-zero");
        vm.prank(user1); redeemer.pack(0);
        vm.prank(user1); redeemer.pack(80_000 * 10**18);
        assertEq(redeemer.bag(user1), 80_000 * 10**18);
        vm.prank(user1); redeemer.pack(10_000 * 10**18);
        assertEq(redeemer.bag(user1), 90_000 * 10**18);
        vm.prank(user1); redeemer.pack(10_000 * 10**18);
        assertEq(redeemer.bag(user1), 100_000 * 10**18);
        vm.expectRevert("Gem/insufficient-balance");
        vm.prank(user1); redeemer.pack(1);
        vm.prank(user2); redeemer.pack(100_000 * 10**18);
        vm.prank(user3); redeemer.pack(100_000 * 10**18);
        vm.prank(user4); redeemer.pack(100_000 * 10**18);

        vm.expectRevert("AllocatorRedeemer/wad-zero");
        vm.prank(user1); redeemer.cash(address(nst), 0);
        vm.prank(user1); redeemer.cash(address(nst), 50_000 * 10**18);
        assertEq(nst.balanceOf(user1), 1_250_000 * 10**18);
        assertEq(redeemer.out(address(nst), user1), 50_000 * 10**18);
        assertEq(redeemer.totOut(address(nst)), 50_000 * 10**18);
        vm.prank(user1); redeemer.cash(address(nst), 50_000 * 10**18);
        assertEq(nst.balanceOf(user1), 2_500_000 * 10**18);
        assertEq(nst.balanceOf(address(redeemer)), 7_500_000 * 10**18);
        assertEq(redeemer.out(address(nst), user1), 100_000 * 10**18);
        assertEq(redeemer.totOut(address(nst)), 100_000 * 10**18);
        vm.prank(user1); redeemer.cash(address(usdc), 100_000 * 10**18);
        assertEq(usdc.balanceOf(user1), 2_500_000 * 10**6);
        assertEq(usdc.balanceOf(address(redeemer)), 7_500_000 * 10**6);
        assertEq(redeemer.out(address(usdc), user1), 100_000 * 10**18);
        assertEq(redeemer.totOut(address(usdc)), 100_000 * 10**18);
        vm.expectRevert("AllocatorRedeemer/insufficient-bag-balance");
        vm.prank(user1); redeemer.cash(address(usdc), 1);

        vm.prank(user2); redeemer.cash(address(nst), 100_000 * 10**18);
        assertEq(nst.balanceOf(user2), 2_500_000 * 10**18);
        assertEq(nst.balanceOf(address(redeemer)), 5_000_000 * 10**18);
        assertEq(redeemer.out(address(nst), user2), 100_000 * 10**18);
        assertEq(redeemer.totOut(address(nst)), 200_000 * 10**18);
        vm.prank(user2); redeemer.cash(address(usdc), 100_000 * 10**18);
        assertEq(usdc.balanceOf(user2), 2_500_000 * 10**6);
        assertEq(usdc.balanceOf(address(redeemer)), 5_000_000 * 10**6);
        assertEq(redeemer.out(address(usdc), user2), 100_000 * 10**18);
        assertEq(redeemer.totOut(address(usdc)), 200_000 * 10**18);

        usdc.mint(address(buffer), 10_000_000 * 10**6); // More USDC comes to the buffer
        redeemer.pull(address(usdc));
        assertEq(usdc.balanceOf(address(redeemer)), 15_000_000 * 10**6);

        vm.prank(user3); redeemer.cash(address(nst), 100_000 * 10**18);
        assertEq(nst.balanceOf(user3), 2_500_000 * 10**18);
        assertEq(nst.balanceOf(address(redeemer)), 2_500_000 * 10**18);
        assertEq(redeemer.out(address(nst), user3), 100_000 * 10**18);
        assertEq(redeemer.totOut(address(nst)), 300_000 * 10**18);
        vm.prank(user3); redeemer.cash(address(usdc), 100_000 * 10**18);
        assertEq(usdc.balanceOf(user3), 7_500_000 * 10**6);
        assertEq(usdc.balanceOf(address(redeemer)), 7_500_000 * 10**6);
        assertEq(redeemer.out(address(usdc), user3), 100_000 * 10**18);
        assertEq(redeemer.totOut(address(usdc)), 300_000 * 10**18);

        usdc.mint(address(buffer), 10_000_000 * 10**6); // More USDC comes to the buffer
        redeemer.pull(address(usdc));
        assertEq(usdc.balanceOf(address(redeemer)), 17_500_000 * 10**6);

        vm.prank(user4); redeemer.cash(address(nst), 100_000 * 10**18);
        assertEq(nst.balanceOf(user4), 2_500_000 * 10**18);
        assertEq(nst.balanceOf(address(redeemer)), 0);
        assertEq(redeemer.out(address(nst), user4), 100_000 * 10**18);
        assertEq(redeemer.totOut(address(nst)), 400_000 * 10**18);
        vm.prank(user4); redeemer.cash(address(usdc), 100_000 * 10**18);
        assertEq(usdc.balanceOf(user4), 17_500_000 * 10**6);
        assertEq(usdc.balanceOf(address(redeemer)), 0);
        assertEq(redeemer.out(address(usdc), user4), 100_000 * 10**18);
        assertEq(redeemer.totOut(address(usdc)), 400_000 * 10**18);
    }
}
