// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import "src/AllocatorOracle.sol";

contract AllocatorOracleTest is DssTest {
    AllocatorOracle public oracle;

    function setUp() public {
        oracle = new AllocatorOracle();
    }

    function testOracle() public {
        (bytes32 val, bool ok) = oracle.peek();
        assertEq(val, bytes32(uint256(10**6 * 10**18)));
        assertTrue(ok);
        assertEq(oracle.read(), bytes32(uint256(10**6 * 10**18)));
    }

    function testPricing() public {
        uint256 par = 1 * 10**27;
        uint256 price = uint256(oracle.read()); // 1 * 10**6 * 10**18;
        uint256 colSupply = 1 * 10**6 * 10**18;
        uint256 colDebt = 1 * 10**6 * 10**45; // Imagine a scenario where the ilk only has 1M debt
        uint256 totDebt = 50 * 10**9 * 10**45; // Imagine a scenario where the tot Supply of DAI is 50B

        console.log("cage(ilk):");
        console.log("");
        uint256 tag = par * 10**18 / price;
        console.log("tag[ilk] =", tag);
        console.log("");
        console.log("skim(ilk, buffer):");
        console.log("");
        uint256 owe = (colDebt / 10**27) * tag / 10**27;
        console.log("owe =", owe);
        uint256 wad = owe <= colSupply ? owe : colSupply;
        console.log("wad =", wad);
        uint256 gap = owe - wad;
        console.log("gap[ilk] =", gap);
        console.log("");
        console.log("flow(ilk):");
        console.log("");
        wad = (colDebt / 10**27) * tag / 10**27;
        console.log("wad =", wad);
        uint256 fix = (wad - gap) * 10**27 / (totDebt / 10**27);
        console.log("fix[ilk] =", fix);
        console.log("");
        console.log("cash(ilk,...):");
        console.log("");
        console.log("1 = wad * fix / 10^27 => wad = 10^27 / fix");
        uint256 amtDaiNeeded = 10**27 / fix;
        console.log("Amount of wei DAI needed to get 1 wei of gem =", amtDaiNeeded);
        assertEq(amtDaiNeeded, 0.00000005 * 10**18);
    }
}
