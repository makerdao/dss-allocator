// AllocatorVault.spec

using AllocatorRoles as roles;
using VatMock as vat;
using JugMock as jug;
using UsdsJoinMock as usdsJoin;
using UsdsMock as usds;

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
    function usds.allowance(address, address) external returns (uint256) envfree;
    function usds.balanceOf(address) external returns (uint256) envfree;
    function usds.totalSupply() external returns (uint256) envfree;
}

definition WAD() returns mathint = 10^18;
definition RAY() returns mathint = 10^27;
definition max_int256() returns mathint = 2^255 - 1;
definition divUp(mathint x, mathint y) returns mathint = x != 0 ? ((x - 1) / y) + 1 : 0;

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    address jugBefore = jug();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    address jugAfter = jug();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "wards[x] changed in an unexpected function";
    assert jugAfter != jugBefore => f.selector == sig:file(bytes32,address).selector, "jug changed in an unexpected function";
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 1, "rely did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "rely did not keep unchanged the rest of wards[x]";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0x65fae35e));
    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = !canCall && wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 0, "deny did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "deny did not keep unchanged the rest of wards[x]";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0x9c52a7f1));
    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = !canCall && wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting file
rule file(bytes32 what, address data) {
    env e;

    file(e, what, data);

    address jugAfter = jug();

    assert jugAfter == data, "file did not set jug";
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

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}

// Verify correct storage changes for non reverting draw
rule draw(uint256 wad) {
    env e;

    mathint usdsTotalSupplyBefore = usds.totalSupply();
    mathint usdsBalanceOfBufferBefore = usds.balanceOf(buffer());
    require usdsBalanceOfBufferBefore <= usdsTotalSupplyBefore;
    mathint vatInkVaultBefore; mathint vatArtVaultBefore;
    vatInkVaultBefore, vatArtVaultBefore = vat.urns(ilk(), currentContract);
    mathint rate = vat.rate() + (jug.duty() - RAY()) * (e.block.timestamp - jug.rho());
    require rate > 0;
    mathint dart = divUp(wad * RAY(), rate);

    draw(e, wad);

    mathint usdsTotalSupplyAfter = usds.totalSupply();
    mathint usdsBalanceOfBufferAfter = usds.balanceOf(buffer());
    mathint vatInkVaultAfter; mathint vatArtVaultAfter;
    vatInkVaultAfter, vatArtVaultAfter = vat.urns(ilk(), currentContract);

    assert vatInkVaultAfter == vatInkVaultBefore, "draw did not keep vat.urns(ilk,vault).ink unchanged";
    assert vatArtVaultAfter == vatArtVaultBefore + dart, "draw did not increase vat.urns(ilk,vault).art by dart";
    assert usdsBalanceOfBufferAfter == usdsBalanceOfBufferBefore + wad, "draw did not increase usds.balanceOf(buffer) by wad";
    assert usdsTotalSupplyAfter == usdsTotalSupplyBefore + wad, "draw did not increase usds.totalSupply() by wad";
}

// Verify revert rules on draw
rule draw_revert(uint256 wad) {
    env e;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0x3b304147));
    mathint wardsSender = wards(e.msg.sender);
    mathint usdsTotalSupply = usds.totalSupply();
    mathint usdsBalanceOfBuffer = usds.balanceOf(buffer());
    require usdsBalanceOfBuffer <= usdsTotalSupply;
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
    mathint vatCanVaultUsdsJoin = vat.can(currentContract, usdsJoin);
    mathint vatDaiUsdsJoin = vat.dai(usdsJoin);

    draw@withrevert(e, wad);

    bool revert1  = e.msg.value > 0;
    bool revert2  = !canCall && wardsSender != 1;
    bool revert3  = wad * RAY() > max_uint256;
    bool revert4  = dart > max_int256();
    bool revert5  = vatArtVault + dart > max_uint256;
    bool revert6  = rate * dart > max_int256();
    bool revert7  = vatDaiVault + rate * dart > max_uint256;
    bool revert8  = vatCanVaultUsdsJoin != 1;
    bool revert9  = vatDaiUsdsJoin + wad * RAY() > max_uint256;
    bool revert10 = usdsTotalSupply + wad > max_uint256;

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5 || revert6 ||
                            revert7 || revert8 || revert9 ||
                            revert10, "Revert rules failed";
}

// Verify correct storage changes for non reverting wipe
rule wipe(uint256 wad) {
    env e;

    mathint usdsTotalSupplyBefore = usds.totalSupply();
    mathint usdsBalanceOfBufferBefore = usds.balanceOf(buffer());
    require usdsBalanceOfBufferBefore <= usdsTotalSupplyBefore;
    mathint vatInkVaultBefore; mathint vatArtVaultBefore;
    vatInkVaultBefore, vatArtVaultBefore = vat.urns(ilk(), currentContract);
    mathint rate = vat.rate() + (jug.duty() - RAY()) * (e.block.timestamp - jug.rho());
    require rate > 0;
    mathint dart = wad * RAY() / rate;

    wipe(e, wad);

    mathint usdsTotalSupplyAfter = usds.totalSupply();
    mathint usdsBalanceOfBufferAfter = usds.balanceOf(buffer());
    mathint vatInkVaultAfter; mathint vatArtVaultAfter;
    vatInkVaultAfter, vatArtVaultAfter = vat.urns(ilk(), currentContract);

    assert vatInkVaultAfter == vatInkVaultBefore, "wipe did not keep vat.urns(ilk,vault).ink unchanged";
    assert vatArtVaultAfter == vatArtVaultBefore - dart, "wipe did not decrease vat.urns(ilk,vault).art by dart";
    assert usdsBalanceOfBufferAfter == usdsBalanceOfBufferBefore - wad, "wipe did not decrease usds.balanceOf(buffer) by wad";
    assert usdsTotalSupplyAfter == usdsTotalSupplyBefore - wad, "wipe did not decrease usds.totalSupply() by wad";
}

// Verify revert rules on wipe
rule wipe_revert(uint256 wad) {
    env e;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0xb38a1620));
    mathint wardsSender = wards(e.msg.sender);
    mathint usdsTotalSupply = usds.totalSupply();
    address buffer = buffer();
    require buffer != currentContract;
    mathint usdsBalanceOfBuffer = usds.balanceOf(buffer);
    mathint usdsBalanceOfVault = usds.balanceOf(currentContract);
    require usdsBalanceOfBuffer + usdsBalanceOfVault <= usdsTotalSupply;
    mathint usdsAllowanceBufferVault = usds.allowance(buffer, currentContract);
    mathint usdsAllowanceVaultUsdsJoin = usds.allowance(currentContract, usdsJoin);
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
    mathint vatDaiUsdsJoin = vat.dai(usdsJoin);

    wipe@withrevert(e, wad);

    bool revert1  = e.msg.value > 0;
    bool revert2  = !canCall && wardsSender != 1;
    bool revert3  = usdsBalanceOfBuffer < to_mathint(wad);
    bool revert4  = usdsAllowanceBufferVault < to_mathint(wad);
    bool revert5  = wad * RAY() > max_uint256;
    bool revert6  = usdsAllowanceVaultUsdsJoin < to_mathint(wad);
    bool revert7  = vatArtVault < dart;
    bool revert8  = vatDaiUsdsJoin < wad * RAY();
    bool revert9  = vatDaiVault + wad * RAY() > max_uint256;
    bool revert10 = rate * dart > max_int256();

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5 || revert6 ||
                            revert7 || revert8 || revert9 ||
                            revert10, "Revert rules failed";
}
