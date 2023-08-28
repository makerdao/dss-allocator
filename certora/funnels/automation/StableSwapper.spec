// StableSwapper.spec

methods {
    function wards(address) external returns (uint256) envfree;
    function buds(address) external returns (uint256) envfree;
    function configs(address, address) external returns (uint128, uint32, uint32, uint96, uint96) envfree;
    function _.swap(address, address, uint256, uint256, address, bytes) external => swapSummary() expect uint256;
}

ghost uint256 swapRetValue;

function swapSummary() returns uint256 {
    return swapRetValue;
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;
    address anyAddr;
    address anyAddr2;

    mathint wardsOtherBefore = wards(other);
    mathint budsBefore = buds(anyAddr);
    mathint numBefore; mathint hopBefore; mathint zzzBefore; mathint lotBefore; mathint reqBefore;
    numBefore, hopBefore, zzzBefore, lotBefore, reqBefore = configs(anyAddr, anyAddr2);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint budsAfter = buds(anyAddr);
    mathint numAfter; mathint hopAfter; mathint zzzAfter; mathint lotAfter; mathint reqAfter;
    numAfter, hopAfter, zzzAfter, lotAfter, reqAfter = configs(anyAddr, anyAddr2);

    assert wardsUsrAfter == 1, "rely did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "rely did not keep unchanged the rest of wards[x]";
    assert budsAfter == budsBefore, "rely did not keep unchanged every buds[x]";
    assert numAfter == numBefore, "rely did not keep unchanged every configs[x][y].num";
    assert hopAfter == hopBefore, "rely did not keep unchanged every configs[x][y].hop";
    assert zzzAfter == zzzBefore, "rely did not keep unchanged every configs[x][y].zzz";
    assert lotAfter == lotBefore, "rely did not keep unchanged every configs[x][y].lot";
    assert reqAfter == reqBefore, "rely did not keep unchanged every configs[x][y].req";
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

    mathint wardsOtherBefore = wards(other);
    mathint budsBefore = buds(anyAddr);
    mathint numBefore; mathint hopBefore; mathint zzzBefore; mathint lotBefore; mathint reqBefore;
    numBefore, hopBefore, zzzBefore, lotBefore, reqBefore = configs(anyAddr, anyAddr2);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint budsAfter = buds(anyAddr);
    mathint numAfter; mathint hopAfter; mathint zzzAfter; mathint lotAfter; mathint reqAfter;
    numAfter, hopAfter, zzzAfter, lotAfter, reqAfter = configs(anyAddr, anyAddr2);

    assert wardsUsrAfter == 0, "deny did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "deny did not keep unchanged the rest of wards[x]";
    assert budsAfter == budsBefore, "deny did not keep unchanged every buds[x]";
    assert numAfter == numBefore, "deny did not keep unchanged every configs[x][y].num";
    assert hopAfter == hopBefore, "deny did not keep unchanged every configs[x][y].hop";
    assert zzzAfter == zzzBefore, "deny did not keep unchanged every configs[x][y].zzz";
    assert lotAfter == lotBefore, "deny did not keep unchanged every configs[x][y].lot";
    assert reqAfter == reqBefore, "deny did not keep unchanged every configs[x][y].req";
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

    mathint wardsBefore = wards(anyAddr);
    mathint budsOtherBefore = buds(other);
    mathint numBefore; mathint hopBefore; mathint zzzBefore; mathint lotBefore; mathint reqBefore;
    numBefore, hopBefore, zzzBefore, lotBefore, reqBefore = configs(anyAddr, anyAddr2);

    kiss(e, usr);

    mathint wardsAfter = wards(anyAddr);
    mathint budsUsrAfter = buds(usr);
    mathint budsOtherAfter = buds(other);
    mathint numAfter; mathint hopAfter; mathint zzzAfter; mathint lotAfter; mathint reqAfter;
    numAfter, hopAfter, zzzAfter, lotAfter, reqAfter = configs(anyAddr, anyAddr2);

    assert wardsAfter == wardsBefore, "kiss did not keep unchanged every wards[x]";
    assert budsUsrAfter == 1, "kiss did not set the buds";
    assert budsOtherAfter == budsOtherBefore, "kiss did not keep unchanged the rest of buds[x]";
    assert numAfter == numBefore, "kiss did not keep unchanged every configs[x][y].num";
    assert hopAfter == hopBefore, "kiss did not keep unchanged every configs[x][y].hop";
    assert zzzAfter == zzzBefore, "kiss did not keep unchanged every configs[x][y].zzz";
    assert lotAfter == lotBefore, "kiss did not keep unchanged every configs[x][y].lot";
    assert reqAfter == reqBefore, "kiss did not keep unchanged every configs[x][y].req";
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

    mathint wardsBefore = wards(anyAddr);
    mathint budsOtherBefore = buds(other);
    mathint numBefore; mathint hopBefore; mathint zzzBefore; mathint lotBefore; mathint reqBefore;
    numBefore, hopBefore, zzzBefore, lotBefore, reqBefore = configs(anyAddr, anyAddr2);

    diss(e, usr);

    mathint wardsAfter = wards(anyAddr);
    mathint budsUsrAfter = buds(usr);
    mathint budsOtherAfter = buds(other);
    mathint numAfter; mathint hopAfter; mathint zzzAfter; mathint lotAfter; mathint reqAfter;
    numAfter, hopAfter, zzzAfter, lotAfter, reqAfter = configs(anyAddr, anyAddr2);

    assert wardsAfter == wardsBefore, "diss did not keep unchanged every wards[x]";
    assert budsUsrAfter == 0, "diss did not set the buds";
    assert budsOtherAfter == budsOtherBefore, "diss did not keep unchanged the rest of buds[x]";
    assert numAfter == numBefore, "diss did not keep unchanged every configs[x][y].num";
    assert hopAfter == hopBefore, "diss did not keep unchanged every configs[x][y].hop";
    assert zzzAfter == zzzBefore, "diss did not keep unchanged every configs[x][y].zzz";
    assert lotAfter == lotBefore, "diss did not keep unchanged every configs[x][y].lot";
    assert reqAfter == reqBefore, "diss did not keep unchanged every configs[x][y].req";
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
rule setConfig(address src, address dst, uint128 num, uint32 hop, uint96 lot, uint96 req) {
    env e;

    address anyAddr;
    address otherAddr;
    address otherAddr2;
    require otherAddr != src || otherAddr2 != dst;

    mathint wardsBefore = wards(anyAddr);
    mathint budsBefore = buds(anyAddr);
    mathint numOtherBefore; mathint hopOtherBefore; mathint zzzOtherBefore; mathint lotOtherBefore; mathint reqOtherBefore;
    numOtherBefore, hopOtherBefore, zzzOtherBefore, lotOtherBefore, reqOtherBefore = configs(otherAddr, otherAddr2);

    setConfig(e, src, dst, num, hop, lot, req);

    mathint wardsAfter = wards(anyAddr);
    mathint budsAfter = buds(anyAddr);
    mathint numSrcDstAfter; mathint hopSrcDstAfter; mathint zzzSrcDstAfter; mathint lotSrcDstAfter; mathint reqSrcDstAfter;
    numSrcDstAfter, hopSrcDstAfter, zzzSrcDstAfter, lotSrcDstAfter, reqSrcDstAfter = configs(src, dst);
    mathint numOtherAfter; mathint hopOtherAfter; mathint zzzOtherAfter; mathint lotOtherAfter; mathint reqOtherAfter;
    numOtherAfter, hopOtherAfter, zzzOtherAfter, lotOtherAfter, reqOtherAfter = configs(otherAddr, otherAddr2);

    assert wardsAfter == wardsBefore, "setConfig did not keep unchanged every wards[x]";
    assert budsAfter == budsBefore, "setConfig did not keep unchanged every buds[x]";
    assert numSrcDstAfter == to_mathint(num), "setConfig did not set configs[src][dst].num to num";
    assert hopSrcDstAfter == to_mathint(hop), "setConfig did not set configs[src][dst].hop to hop";
    assert zzzSrcDstAfter == 0, "setConfig did not set configs[src][dst].zzz to 0";
    assert lotSrcDstAfter == to_mathint(lot), "setConfig did not set configs[src][dst].lot to lot";
    assert reqSrcDstAfter == to_mathint(req), "setConfig did not set configs[src][dst].req to req";
    assert numOtherAfter == numOtherBefore, "setConfig did not keep unchanged the rest of configs[x][y].num";
    assert hopOtherAfter == hopOtherBefore, "setConfig did not keep unchanged the rest of configs[x][y].hop";
    assert zzzOtherAfter == zzzOtherBefore, "setConfig did not keep unchanged the rest of configs[x][y].zzz";
    assert lotOtherAfter == lotOtherBefore, "setConfig did not keep unchanged the rest of configs[x][y].lot";
    assert reqOtherAfter == reqOtherBefore, "setConfig did not keep unchanged the rest of configs[x][y].req";
}

// Verify revert rules on setConfig
rule setConfig_revert(address src, address dst, uint128 num, uint32 hop, uint96 lot, uint96 req) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    setConfig@withrevert(e, src, dst, num, hop, lot, req);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting swap
rule swap(address src, address dst, uint256 minOut, address callee, bytes data) {
    env e;

    address anyAddr;
    address otherAddr;
    address otherAddr2;
    require otherAddr != src || otherAddr2 != dst;

    require e.block.timestamp <= max_uint32;

    mathint wardsBefore = wards(anyAddr);
    mathint budsBefore = buds(anyAddr);
    mathint numSrcDstBefore; mathint hopSrcDstBefore; mathint zzzSrcDstBefore; mathint lotSrcDstBefore; mathint reqSrcDstBefore;
    numSrcDstBefore, hopSrcDstBefore, zzzSrcDstBefore, lotSrcDstBefore, reqSrcDstBefore = configs(src, dst);
    mathint numOtherBefore; mathint hopOtherBefore; mathint zzzOtherBefore; mathint lotOtherBefore; mathint reqOtherBefore;
    numOtherBefore, hopOtherBefore, zzzOtherBefore, lotOtherBefore, reqOtherBefore = configs(otherAddr, otherAddr2);

    swap(e, src, dst, minOut, callee, data);

    mathint wardsAfter = wards(anyAddr);
    mathint budsAfter = buds(anyAddr);
    mathint numSrcDstAfter; mathint hopSrcDstAfter; mathint zzzSrcDstAfter; mathint lotSrcDstAfter; mathint reqSrcDstAfter;
    numSrcDstAfter, hopSrcDstAfter, zzzSrcDstAfter, lotSrcDstAfter, reqSrcDstAfter = configs(src, dst);
    mathint numOtherAfter; mathint hopOtherAfter; mathint zzzOtherAfter; mathint lotOtherAfter; mathint reqOtherAfter;
    numOtherAfter, hopOtherAfter, zzzOtherAfter, lotOtherAfter, reqOtherAfter = configs(otherAddr, otherAddr2);

    assert wardsAfter == wardsBefore, "swap did not keep unchanged every wards[x]";
    assert budsAfter == budsBefore, "swap did not keep unchanged every buds[x]";
    assert numSrcDstAfter == numSrcDstBefore - 1, "swap did not decrease configs[src][dst].num by 1";
    assert hopSrcDstAfter == hopSrcDstBefore, "swap did not set configs[src][dst].hop to hop";
    assert zzzSrcDstAfter == to_mathint(e.block.timestamp), "swap did not set configs[src][dst].zzz to block.timestamp";
    assert lotSrcDstAfter == lotSrcDstBefore, "swap did not set configs[src][dst].lot to lot";
    assert reqSrcDstAfter == reqSrcDstBefore, "swap did not set configs[src][dst].req to req";
    assert numOtherAfter == numOtherBefore, "swap did not keep unchanged the rest of configs[x][y].num";
    assert hopOtherAfter == hopOtherBefore, "swap did not keep unchanged the rest of configs[x][y].hop";
    assert zzzOtherAfter == zzzOtherBefore, "swap did not keep unchanged the rest of configs[x][y].zzz";
    assert lotOtherAfter == lotOtherBefore, "swap did not keep unchanged the rest of configs[x][y].lot";
    assert reqOtherAfter == reqOtherBefore, "swap did not keep unchanged the rest of configs[x][y].req";
}

// Verify revert rules on swap
rule swap_revert(address src, address dst, uint256 minOut, address callee, bytes data) {
    env e;

    require data.length < max_uint32;
    require e.block.timestamp <= max_uint32;

    mathint budsSender = buds(e.msg.sender);
    mathint numSrcDst; mathint hopSrcDst; mathint zzzSrcDst; mathint lotSrcDst; mathint reqSrcDst;
    numSrcDst, hopSrcDst, zzzSrcDst, lotSrcDst, reqSrcDst = configs(src, dst);

    swap@withrevert(e, src, dst, minOut, callee, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = budsSender != 1;
    bool revert3 = numSrcDst == 0;
    bool revert4 = to_mathint(e.block.timestamp) < zzzSrcDst + hopSrcDst;
    bool revert5 = to_mathint(minOut) > 0 && to_mathint(minOut) < reqSrcDst;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5, "Revert rules are not covering all the cases";
}
