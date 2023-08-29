// StableDepositorUniV3.spec

methods {
    function wards(address) external returns (uint256) envfree;
    function buds(address) external returns (uint256) envfree;
    function configs(address, address, uint24, int24, int24) external returns (int32, uint32, uint96, uint96, uint96, uint96, uint32) envfree;
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;
    address anyAddr;
    address anyAddr2;
    uint24 anyUint24;
    int24 anyInt24;
    int24 anyInt242;

    mathint wardsOtherBefore = wards(other);
    mathint budsBefore = buds(anyAddr);
    mathint numBefore; mathint zzzBefore; mathint amt0Before; mathint amt1Before; mathint req0Before; mathint req1Before; mathint hopBefore;
    numBefore, zzzBefore, amt0Before, amt1Before, req0Before, req1Before, hopBefore = configs(anyAddr, anyAddr2, anyUint24, anyInt24, anyInt242);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint budsAfter = buds(anyAddr);
    mathint numAfter; mathint zzzAfter; mathint amt0After; mathint amt1After; mathint req0After; mathint req1After; mathint hopAfter;
    numAfter, zzzAfter, amt0After, amt1After, req0After, req1After, hopAfter = configs(anyAddr, anyAddr2, anyUint24, anyInt24, anyInt242);

    assert wardsUsrAfter == 1, "rely did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "rely did not keep unchanged the rest of wards[x]";
    assert budsAfter == budsBefore, "rely did not keep unchanged every buds[x]";
    assert numAfter == numBefore, "rely did not keep unchanged every configs[x][y][z][a][b].num";
    assert zzzAfter == zzzBefore, "rely did not keep unchanged every configs[x][y][z][a][b].zzz";
    assert amt0After == amt0Before, "rely did not keep unchanged every configs[x][y][z][a][b].amt0";
    assert amt1After == amt1Before, "rely did not keep unchanged every configs[x][y][z][a][b].amt1";
    assert req0After == req0Before, "rely did not keep unchanged every configs[x][y][z][a][b].req0";
    assert req1After == req1Before, "rely did not keep unchanged every configs[x][y][z][a][b].req1";
    assert hopAfter == hopBefore, "rely did not keep unchanged every configs[x][y][z][a][b].hop";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;
    address anyAddr;
    address anyAddr2;
    uint24 anyUint24;
    int24 anyInt24;
    int24 anyInt242;

    mathint wardsOtherBefore = wards(other);
    mathint budsBefore = buds(anyAddr);
    mathint numBefore; mathint zzzBefore; mathint amt0Before; mathint amt1Before; mathint req0Before; mathint req1Before; mathint hopBefore;
    numBefore, zzzBefore, amt0Before, amt1Before, req0Before, req1Before, hopBefore = configs(anyAddr, anyAddr2, anyUint24, anyInt24, anyInt242);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint budsAfter = buds(anyAddr);
    mathint numAfter; mathint zzzAfter; mathint amt0After; mathint amt1After; mathint req0After; mathint req1After; mathint hopAfter;
    numAfter, zzzAfter, amt0After, amt1After, req0After, req1After, hopAfter = configs(anyAddr, anyAddr2, anyUint24, anyInt24, anyInt242);

    assert wardsUsrAfter == 0, "deny did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "deny did not keep unchanged the rest of wards[x]";
    assert budsAfter == budsBefore, "deny did not keep unchanged every buds[x]";
    assert numAfter == numBefore, "deny did not keep unchanged every configs[x][y][z][a][b].num";
    assert zzzAfter == zzzBefore, "deny did not keep unchanged every configs[x][y][z][a][b].zzz";
    assert amt0After == amt0Before, "deny did not keep unchanged every configs[x][y][z][a][b].amt0";
    assert amt1After == amt1Before, "deny did not keep unchanged every configs[x][y][z][a][b].amt1";
    assert req0After == req0Before, "deny did not keep unchanged every configs[x][y][z][a][b].req0";
    assert req1After == req1Before, "deny did not keep unchanged every configs[x][y][z][a][b].req1";
    assert hopAfter == hopBefore, "deny did not keep unchanged every configs[x][y][z][a][b].hop";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting kiss
rule kiss(address usr) {
    env e;

    address other;
    require other != usr;
    address anyAddr;
    address anyAddr2;
    uint24 anyUint24;
    int24 anyInt24;
    int24 anyInt242;

    mathint wardsBefore = wards(anyAddr);
    mathint budsOtherBefore = buds(other);
    mathint numBefore; mathint zzzBefore; mathint amt0Before; mathint amt1Before; mathint req0Before; mathint req1Before; mathint hopBefore;
    numBefore, zzzBefore, amt0Before, amt1Before, req0Before, req1Before, hopBefore = configs(anyAddr, anyAddr2, anyUint24, anyInt24, anyInt242);

    kiss(e, usr);

    mathint wardsAfter = wards(anyAddr);
    mathint budsUsrAfter = buds(usr);
    mathint budsOtherAfter = buds(other);
    mathint numAfter; mathint zzzAfter; mathint amt0After; mathint amt1After; mathint req0After; mathint req1After; mathint hopAfter;
    numAfter, zzzAfter, amt0After, amt1After, req0After, req1After, hopAfter = configs(anyAddr, anyAddr2, anyUint24, anyInt24, anyInt242);

    assert wardsAfter == wardsBefore, "kiss did not keep unchanged every wards[x]";
    assert budsUsrAfter == 1, "kiss did not set the buds";
    assert budsOtherAfter == budsOtherBefore, "kiss did not keep unchanged the rest of buds[x]";
    assert numAfter == numBefore, "kiss did not keep unchanged every configs[x][y][z][a][b].num";
    assert zzzAfter == zzzBefore, "kiss did not keep unchanged every configs[x][y][z][a][b].zzz";
    assert amt0After == amt0Before, "kiss did not keep unchanged every configs[x][y][z][a][b].amt0";
    assert amt1After == amt1Before, "kiss did not keep unchanged every configs[x][y][z][a][b].amt1";
    assert req0After == req0Before, "kiss did not keep unchanged every configs[x][y][z][a][b].req0";
    assert req1After == req1Before, "kiss did not keep unchanged every configs[x][y][z][a][b].req1";
    assert hopAfter == hopBefore, "kiss did not keep unchanged every configs[x][y][z][a][b].hop";
}

// Verify revert rules on kiss
rule kiss_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    kiss@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting diss
rule diss(address usr) {
    env e;

    address other;
    require other != usr;
    address anyAddr;
    address anyAddr2;
    uint24 anyUint24;
    int24 anyInt24;
    int24 anyInt242;

    mathint wardsBefore = wards(anyAddr);
    mathint budsOtherBefore = buds(other);
    mathint numBefore; mathint zzzBefore; mathint amt0Before; mathint amt1Before; mathint req0Before; mathint req1Before; mathint hopBefore;
    numBefore, zzzBefore, amt0Before, amt1Before, req0Before, req1Before, hopBefore = configs(anyAddr, anyAddr2, anyUint24, anyInt24, anyInt242);

    diss(e, usr);

    mathint wardsAfter = wards(anyAddr);
    mathint budsUsrAfter = buds(usr);
    mathint budsOtherAfter = buds(other);
    mathint numAfter; mathint zzzAfter; mathint amt0After; mathint amt1After; mathint req0After; mathint req1After; mathint hopAfter;
    numAfter, zzzAfter, amt0After, amt1After, req0After, req1After, hopAfter = configs(anyAddr, anyAddr2, anyUint24, anyInt24, anyInt242);

    assert wardsAfter == wardsBefore, "diss did not keep unchanged every wards[x]";
    assert budsUsrAfter == 0, "diss did not set the buds";
    assert budsOtherAfter == budsOtherBefore, "diss did not keep unchanged the rest of buds[x]";
    assert numAfter == numBefore, "diss did not keep unchanged every configs[x][y][z][a][b].num";
    assert zzzAfter == zzzBefore, "diss did not keep unchanged every configs[x][y][z][a][b].zzz";
    assert amt0After == amt0Before, "diss did not keep unchanged every configs[x][y][z][a][b].amt0";
    assert amt1After == amt1Before, "diss did not keep unchanged every configs[x][y][z][a][b].amt1";
    assert req0After == req0Before, "diss did not keep unchanged every configs[x][y][z][a][b].req0";
    assert req1After == req1Before, "diss did not keep unchanged every configs[x][y][z][a][b].req1";
    assert hopAfter == hopBefore, "diss did not keep unchanged every configs[x][y][z][a][b].hop";
}

// Verify revert rules on diss
rule diss_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    diss@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting setConfig
rule setConfig(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, int32 num, uint32 hop, uint96 amt0, uint96 amt1, uint96 req0, uint96 req1) {
    env e;

    address anyAddr;
    address otherAddr;
    address otherAddr2;
    uint24 otherUint24;
    int24 otherInt24;
    int24 otherInt242;
    require otherAddr != gem0 || otherAddr2 != gem1 || fee != otherUint24 || tickLower != otherInt24 || tickUpper != otherInt242;

    mathint wardsBefore = wards(anyAddr);
    mathint budsBefore = buds(anyAddr);
    mathint numOtherBefore; mathint zzzOtherBefore; mathint amt0OtherBefore; mathint amt1OtherBefore; mathint req0OtherBefore; mathint req1OtherBefore; mathint hopOtherBefore;
    numOtherBefore, zzzOtherBefore, amt0OtherBefore, amt1OtherBefore, req0OtherBefore, req1OtherBefore, hopOtherBefore = configs(otherAddr, otherAddr2, otherUint24, otherInt24, otherInt242);

    setConfig(e, gem0, gem1, fee, tickLower, tickUpper, num, hop, amt0, amt1, req0, req1);

    mathint wardsAfter = wards(anyAddr);
    mathint budsAfter = buds(anyAddr);
    mathint numGem0Gem1After; mathint zzzGem0Gem1After; mathint amt0Gem0Gem1After; mathint amt1Gem0Gem1After; mathint req0Gem0Gem1After; mathint req1Gem0Gem1After; mathint hopGem0Gem1After;
    numGem0Gem1After, zzzGem0Gem1After, amt0Gem0Gem1After, amt1Gem0Gem1After, req0Gem0Gem1After, req1Gem0Gem1After, hopGem0Gem1After = configs(gem0, gem1, fee, tickLower, tickUpper);
    mathint numOtherAfter; mathint zzzOtherAfter; mathint amt0OtherAfter; mathint amt1OtherAfter; mathint req0OtherAfter; mathint req1OtherAfter; mathint hopOtherAfter;
    numOtherAfter, zzzOtherAfter, amt0OtherAfter, amt1OtherAfter, req0OtherAfter, req1OtherAfter, hopOtherAfter = configs(otherAddr, otherAddr2, otherUint24, otherInt24, otherInt242);

    assert wardsAfter == wardsBefore, "setConfig did not keep unchanged every wards[x]";
    assert budsAfter == budsBefore, "setConfig did not keep unchanged every buds[x]";
    assert numGem0Gem1After == to_mathint(num), "setConfig did not set configs[gem0][gem1][fee][tickLower][tickUpper].num to num";
    assert zzzGem0Gem1After == 0, "setConfig did not set configs[gem0][gem1][fee][tickLower][tickUpper].zzz to 0";
    assert amt0Gem0Gem1After == to_mathint(amt0), "setConfig did not set configs[gem0][gem1][fee][tickLower][tickUpper].amt0 to amt0";
    assert amt1Gem0Gem1After == to_mathint(amt1), "setConfig did not set configs[gem0][gem1][fee][tickLower][tickUpper].amt1 to amt1";
    assert req0Gem0Gem1After == to_mathint(req0), "setConfig did not set configs[gem0][gem1][fee][tickLower][tickUpper].req0 to req0";
    assert req1Gem0Gem1After == to_mathint(req1), "setConfig did not set configs[gem0][gem1][fee][tickLower][tickUpper].req1 to req1";
    assert hopGem0Gem1After == to_mathint(hop), "setConfig did not set configs[gem0][gem1][fee][tickLower][tickUpper].hop to hop";
    assert numOtherAfter == numOtherBefore, "setConfig did not keep the rest of configs[x][y][z][a][b].num";
    assert zzzOtherAfter == zzzOtherBefore, "setConfig did not keep the rest of configs[x][y][z][a][b].zzz";
    assert amt0OtherAfter == amt0OtherBefore, "setConfig did not keep the rest of configs[x][y][z][a][b].amt0";
    assert amt1OtherAfter == amt1OtherBefore, "setConfig did not keep the rest of configs[x][y][z][a][b].amt1";
    assert req0OtherAfter == req0OtherBefore, "setConfig did not keep the rest of configs[x][y][z][a][b].req0";
    assert req1OtherAfter == req1OtherBefore, "setConfig did not keep the rest of configs[x][y][z][a][b].req1";
    assert hopOtherAfter == hopOtherBefore, "setConfig did not keep the rest of configs[x][y][z][a][b].hop";
}

// Verify revert rules on setConfig
rule setConfig_revert(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, int32 num, uint32 hop, uint96 amt0, uint96 amt1, uint96 req0, uint96 req1) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    setConfig@withrevert(e, gem0, gem1, fee, tickLower, tickUpper, num, hop, amt0, amt1, req0, req1);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = gem0 >= gem1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases";
}