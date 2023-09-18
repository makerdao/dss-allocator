// AllocatorVault.spec

using AllocatorRoles as roles;
using VatMock as vat;
using JugMock as jug;
using NstJoinMock as nstJoin;
using NstMock as nst;

methods {
    function ilk() external returns (bytes32) envfree;
    function wards(address) external returns (uint256) envfree;
    function jug() external returns (address) envfree;
    function buffer() external returns (address) envfree;
    function roles.canCall(bytes32, address, address, bytes4) external returns (bool) envfree;
    function vat.can(address, address) external returns (uint256) envfree;
    function vat.dai(address) external returns (uint256) envfree;
    function vat.gem(bytes32, address) external returns (uint256) envfree;
    function vat.urns(bytes32, address) external returns (uint256, uint256) envfree;
    function vat.rate() external returns (uint256) envfree;
    function jug.duty() external returns (uint256) envfree;
    function jug.rho() external returns (uint256) envfree;
    function nst.allowance(address, address) external returns (uint256) envfree;
    function nst.balanceOf(address) external returns (uint256) envfree;
    function nst.totalSupply() external returns (uint256) envfree;
}

definition WAD() returns mathint = 10^18;
definition RAY() returns mathint = 10^27;
definition max_int256() returns mathint = 2^255 - 1;
definition divUp(mathint x, mathint y) returns mathint = x != 0 ? ((x - 1) / y) + 1 : 0;

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);
    address jugBefore = jug();

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    address jugAfter = jug();

    assert wardsUsrAfter == 1, "rely did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "rely did not keep unchanged the rest of wards[x]";
    assert jugAfter == jugBefore, "rely did not keep unchanged jug";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0x65fae35e));
    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = !canCall && wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);
    address jugBefore = jug();

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    address jugAfter = jug();

    assert wardsUsrAfter == 0, "deny did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "deny did not keep unchanged the rest of wards[x]";
    assert jugAfter == jugBefore, "deny did not keep unchanged jug";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0x9c52a7f1));
    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = !canCall && wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting file
rule file(bytes32 what, address data) {
    env e;

    address any;

    mathint wardsBefore = wards(any);

    file(e, what, data);

    mathint wardsAfter = wards(any);
    address jugAfter = jug();

    assert wardsAfter == wardsBefore, "file did not keep unchanged every wards[x]";
    assert jugAfter == data, "file did not keep unchanged jug";
}

// Verify revert rules on file
rule file_revert(bytes32 what, address data) {
    env e;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0xd4e8be83));
    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = !canCall && wardsSender != 1;
    bool revert3 = what != to_bytes32(0x6a75670000000000000000000000000000000000000000000000000000000000);

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting draw
rule draw(uint256 wad) {
    env e;

    address any;

    mathint wardsBefore = wards(any);
    address jugBefore = jug();
    mathint nstTotalSupplyBefore = nst.totalSupply();
    mathint nstBalanceOfBufferBefore = nst.balanceOf(buffer());
    require nstBalanceOfBufferBefore <= nstTotalSupplyBefore;
    mathint vatInkVaultBefore; mathint vatArtVaultBefore;
    vatInkVaultBefore, vatArtVaultBefore = vat.urns(ilk(), currentContract);
    mathint rate = vat.rate() + (jug.duty() - RAY()) * (e.block.timestamp - jug.rho());
    require rate > 0;
    mathint dart = divUp(wad * RAY(), rate);

    draw(e, wad);

    mathint wardsAfter = wards(any);
    address jugAfter = jug();
    mathint nstTotalSupplyAfter = nst.totalSupply();
    mathint nstBalanceOfBufferAfter = nst.balanceOf(buffer());
    mathint vatInkVaultAfter; mathint vatArtVaultAfter;
    vatInkVaultAfter, vatArtVaultAfter = vat.urns(ilk(), currentContract);

    assert wardsAfter == wardsBefore, "draw did not keep unchanged every wards[x]";
    assert jugAfter == jugBefore, "draw did not keep unchanged jug";
    assert vatInkVaultAfter == vatInkVaultBefore, "draw did not keep vat.urns(ilk,vault).ink unchanged";
    assert vatArtVaultAfter == vatArtVaultBefore + dart, "draw did not increase vat.urns(ilk,vault).art by dart";
    assert nstBalanceOfBufferAfter == nstBalanceOfBufferBefore + wad, "draw did not increase nst.balanceOf(buffer) by wad";
    assert nstTotalSupplyAfter == nstTotalSupplyBefore + wad, "draw did not increase nst.totalSupply() by wad";
}

// Verify revert rules on draw
rule draw_revert(uint256 wad) {
    env e;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0x3b304147));
    mathint wardsSender = wards(e.msg.sender);
    mathint nstTotalSupply = nst.totalSupply();
    mathint nstBalanceOfBuffer = nst.balanceOf(buffer());
    require nstBalanceOfBuffer <= nstTotalSupply;
    mathint vatInkVault; mathint vatArtVault;
    vatInkVault, vatArtVault = vat.urns(ilk(), currentContract);
    mathint duty = jug.duty();
    require duty >= RAY();
    mathint rho = jug.rho();
    require to_mathint(e.block.timestamp) >= rho;
    mathint rate = vat.rate() + (duty - RAY()) * (e.block.timestamp - jug.rho());
    require rate > 0 && rate <= max_int256();
    mathint dart = divUp(wad * RAY(), rate);
    mathint vatDaiVault = vat.dai(currentContract);
    mathint vatCanVaultNstJoin = vat.can(currentContract, nstJoin);
    mathint vatDaiNstJoin = vat.dai(nstJoin);

    draw@withrevert(e, wad);

    bool revert1  = e.msg.value > 0;
    bool revert2  = !canCall && wardsSender != 1;
    bool revert3  = wad * RAY() > max_uint256;
    bool revert4  = dart > max_int256();
    bool revert5  = vatArtVault + dart > max_uint256;
    bool revert6  = rate * dart > max_int256();
    bool revert7  = vatDaiVault + rate * dart > max_uint256;
    bool revert8  = vatCanVaultNstJoin != 1;
    bool revert9  = vatDaiNstJoin + wad * RAY() > max_uint256;
    bool revert10 = nstTotalSupply + wad > max_uint256;

    assert revert1  => lastReverted, "revert1 failed";
    assert revert2  => lastReverted, "revert2 failed";
    assert revert3  => lastReverted, "revert3 failed";
    assert revert4  => lastReverted, "revert4 failed";
    assert revert5  => lastReverted, "revert5 failed";
    assert revert6  => lastReverted, "revert6 failed";
    assert revert7  => lastReverted, "revert7 failed";
    assert revert8  => lastReverted, "revert8 failed";
    assert revert9  => lastReverted, "revert9 failed";
    assert revert10 => lastReverted, "revert10 failed";
    assert lastReverted => revert1  || revert2 || revert3 ||
                           revert4  || revert5 || revert6 ||
                           revert7  || revert8 || revert9 ||
                           revert10, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting wipe
rule wipe(uint256 wad) {
    env e;

    address any;

    mathint wardsBefore = wards(any);
    address jugBefore = jug();
    mathint nstTotalSupplyBefore = nst.totalSupply();
    mathint nstBalanceOfBufferBefore = nst.balanceOf(buffer());
    require nstBalanceOfBufferBefore <= nstTotalSupplyBefore;
    mathint vatInkVaultBefore; mathint vatArtVaultBefore;
    vatInkVaultBefore, vatArtVaultBefore = vat.urns(ilk(), currentContract);
    mathint rate = vat.rate() + (jug.duty() - RAY()) * (e.block.timestamp - jug.rho());
    require rate > 0;
    mathint dart = wad * RAY() / rate;

    wipe(e, wad);

    mathint wardsAfter = wards(any);
    address jugAfter = jug();
    mathint nstTotalSupplyAfter = nst.totalSupply();
    mathint nstBalanceOfBufferAfter = nst.balanceOf(buffer());
    mathint vatInkVaultAfter; mathint vatArtVaultAfter;
    vatInkVaultAfter, vatArtVaultAfter = vat.urns(ilk(), currentContract);

    assert wardsAfter == wardsBefore, "wipe did not keep unchanged every wards[x]";
    assert jugAfter == jugBefore, "wipe did not keep unchanged jug";
    assert vatInkVaultAfter == vatInkVaultBefore, "wipe did not keep vat.urns(ilk,vault).ink unchanged";
    assert vatArtVaultAfter == vatArtVaultBefore - dart, "wipe did not decrease vat.urns(ilk,vault).art by dart";
    assert nstBalanceOfBufferAfter == nstBalanceOfBufferBefore - wad, "wipe did not decrease nst.balanceOf(buffer) by wad";
    assert nstTotalSupplyAfter == nstTotalSupplyBefore - wad, "wipe did not decrease nst.totalSupply() by wad";
}

// Verify revert rules on wipe
rule wipe_revert(uint256 wad) {
    env e;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0xb38a1620));
    mathint wardsSender = wards(e.msg.sender);
    mathint nstTotalSupply = nst.totalSupply();
    address buffer = buffer();
    require buffer != currentContract;
    mathint nstBalanceOfBuffer = nst.balanceOf(buffer);
    mathint nstBalanceOfVault = nst.balanceOf(currentContract);
    require nstBalanceOfBuffer + nstBalanceOfVault <= nstTotalSupply;
    mathint nstAllowanceBufferVault = nst.allowance(buffer, currentContract);
    mathint nstAllowanceVaultNstJoin = nst.allowance(currentContract, nstJoin);
    mathint vatInkVault; mathint vatArtVault;
    vatInkVault, vatArtVault = vat.urns(ilk(), currentContract);
    mathint duty = jug.duty();
    require duty >= RAY();
    mathint rho = jug.rho();
    require to_mathint(e.block.timestamp) >= rho;
    mathint rate = vat.rate() + (duty - RAY()) * (e.block.timestamp - jug.rho());
    require rate > 0 && rate <= max_int256();
    mathint dart = wad * RAY() / rate;
    mathint vatDaiVault = vat.dai(currentContract);
    mathint vatDaiNstJoin = vat.dai(nstJoin);

    wipe@withrevert(e, wad);

    bool revert1  = e.msg.value > 0;
    bool revert2  = !canCall && wardsSender != 1;
    bool revert3  = nstBalanceOfBuffer < to_mathint(wad);
    bool revert4  = nstAllowanceBufferVault < to_mathint(wad);
    bool revert5  = wad * RAY() > max_uint256;
    bool revert6  = nstAllowanceVaultNstJoin < to_mathint(wad);
    bool revert7  = vatArtVault < dart;
    bool revert8  = vatDaiNstJoin < wad * RAY();
    bool revert9  = vatDaiVault + wad * RAY() > max_uint256;
    bool revert10 = rate * dart > max_int256();

    assert revert1  => lastReverted, "revert1 failed";
    assert revert2  => lastReverted, "revert2 failed";
    assert revert3  => lastReverted, "revert3 failed";
    assert revert4  => lastReverted, "revert4 failed";
    assert revert5  => lastReverted, "revert5 failed";
    assert revert6  => lastReverted, "revert6 failed";
    assert revert7  => lastReverted, "revert7 failed";
    assert revert8  => lastReverted, "revert8 failed";
    assert revert9  => lastReverted, "revert9 failed";
    assert revert10 => lastReverted, "revert10 failed";
    assert lastReverted => revert1  || revert2 || revert3 ||
                           revert4  || revert5 || revert6 ||
                           revert7  || revert8 || revert9 ||
                           revert10, "Revert rules are not covering all the cases";
}
