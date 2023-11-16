// StableSwapper.spec

methods {
    function wards(address) external returns (uint256) envfree;
    function buds(address) external returns (uint256) envfree;
    function configs(address, address) external returns (uint128, uint32, uint32, uint96, uint96) envfree;
    function swapper() external returns (address) envfree;
    function _.swap(address src, address dst, uint256 lot, uint256 minOut, address callee, bytes data) external => swapSummary(calledContract, src, dst, lot, minOut, callee, data) expect uint256;
}

ghost mathint swapCounter;
ghost address swapAddr;
ghost uint256 swapRetValue;
ghost address swapSrc;
ghost address swapDst;
ghost uint256 swapLot;
ghost uint256 swapMinOut;
ghost address swapCallee;
ghost uint256 swapDataLength;
function swapSummary(address addr, address src, address dst, uint256 lot, uint256 minOut, address callee, bytes data) returns uint256 {
    swapCounter = swapCounter + 1;
    swapAddr = addr;
    swapSrc = src;
    swapDst = dst;
    swapLot = lot;
    swapMinOut = minOut;
    swapCallee = callee;
    swapDataLength = data.length;
    return swapRetValue;
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;
    address anyAddr_2;

    mathint wardsBefore = wards(anyAddr);
    mathint budsBefore = buds(anyAddr);
    mathint numBefore; mathint hopBefore; mathint zzzBefore; mathint lotBefore; mathint reqBefore;
    numBefore, hopBefore, zzzBefore, lotBefore, reqBefore = configs(anyAddr, anyAddr_2);

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint budsAfter = buds(anyAddr);
    mathint numAfter; mathint hopAfter; mathint zzzAfter; mathint lotAfter; mathint reqAfter;
    numAfter, hopAfter, zzzAfter, lotAfter, reqAfter = configs(anyAddr, anyAddr_2);

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "wards[x] changed in an unexpected function";
    assert budsAfter != budsBefore => f.selector == sig:kiss(address).selector || f.selector == sig:diss(address).selector, "buds[x] changed in an unexpected function";
    assert numAfter != numBefore => f.selector == sig:setConfig(address,address,uint128,uint32,uint96,uint96).selector || f.selector == sig:swap(address,address,uint256,address,bytes).selector, "configs[x][y].num changed in an unexpected function";
    assert hopAfter != hopBefore => f.selector == sig:setConfig(address,address,uint128,uint32,uint96,uint96).selector, "configs[x][y].hop changed in an unexpected function";
    assert zzzAfter != zzzBefore => f.selector == sig:setConfig(address,address,uint128,uint32,uint96,uint96).selector || f.selector == sig:swap(address,address,uint256,address,bytes).selector, "configs[x][y].zzz changed in an unexpected function";
    assert lotAfter != lotBefore => f.selector == sig:setConfig(address,address,uint128,uint32,uint96,uint96).selector, "configs[x][y].lot changed in an unexpected function";
    assert reqAfter != reqBefore => f.selector == sig:setConfig(address,address,uint128,uint32,uint96,uint96).selector, "configs[x][y].req changed in an unexpected function";
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

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

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

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting kiss
rule kiss(address usr) {
    env e;

    address other;
    require other != usr;

    mathint budsOtherBefore = buds(other);

    kiss(e, usr);

    mathint budsUsrAfter = buds(usr);
    mathint budsOtherAfter = buds(other);

    assert budsUsrAfter == 1, "kiss did not set the buds";
    assert budsOtherAfter == budsOtherBefore, "kiss did not keep unchanged the rest of buds[x]";
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
    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting diss
rule diss(address usr) {
    env e;

    address other;
    require other != usr;

    mathint budsOtherBefore = buds(other);

    diss(e, usr);

    mathint budsUsrAfter = buds(usr);
    mathint budsOtherAfter = buds(other);

    assert budsUsrAfter == 0, "diss did not set the buds";
    assert budsOtherAfter == budsOtherBefore, "diss did not keep unchanged the rest of buds[x]";
}

// Verify revert rules on diss
rule diss_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    diss@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting setConfig
rule setConfig(address src, address dst, uint128 num, uint32 hop, uint96 lot, uint96 req) {
    env e;

    address otherAddr;
    address otherAddr_2;
    require otherAddr != src || otherAddr_2 != dst;

    mathint numOtherBefore; mathint hopOtherBefore; mathint zzzOtherBefore; mathint lotOtherBefore; mathint reqOtherBefore;
    numOtherBefore, hopOtherBefore, zzzOtherBefore, lotOtherBefore, reqOtherBefore = configs(otherAddr, otherAddr_2);

    setConfig(e, src, dst, num, hop, lot, req);

    mathint numSrcDstAfter; mathint hopSrcDstAfter; mathint zzzSrcDstAfter; mathint lotSrcDstAfter; mathint reqSrcDstAfter;
    numSrcDstAfter, hopSrcDstAfter, zzzSrcDstAfter, lotSrcDstAfter, reqSrcDstAfter = configs(src, dst);
    mathint numOtherAfter; mathint hopOtherAfter; mathint zzzOtherAfter; mathint lotOtherAfter; mathint reqOtherAfter;
    numOtherAfter, hopOtherAfter, zzzOtherAfter, lotOtherAfter, reqOtherAfter = configs(otherAddr, otherAddr_2);

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

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting swap
rule swap(address src, address dst, uint256 minOut, address callee, bytes data) {
    env e;

    address otherAddr;
    address otherAddr_2;
    require otherAddr != src || otherAddr_2 != dst;

    require e.block.timestamp <= max_uint32;

    mathint a; mathint b; mathint c;

    mathint numSrcDstBefore; mathint lotSrcDst; mathint reqSrcDst;
    numSrcDstBefore, a, b, lotSrcDst, reqSrcDst = configs(src, dst);
    mathint numOtherBefore; mathint zzzOtherBefore;
    numOtherBefore, a, zzzOtherBefore, b, c = configs(otherAddr, otherAddr_2);

    mathint swapCounterBefore = swapCounter;

    swap(e, src, dst, minOut, callee, data);

    mathint numSrcDstAfter; mathint zzzSrcDstAfter;
    numSrcDstAfter, a, zzzSrcDstAfter, b, c = configs(src, dst);
    mathint numOtherAfter; mathint zzzOtherAfter;
    numOtherAfter, a, zzzOtherAfter, b, c = configs(otherAddr, otherAddr_2);

    assert numSrcDstAfter == numSrcDstBefore - 1, "swap did not decrease configs[src][dst].num by 1";
    assert zzzSrcDstAfter == to_mathint(e.block.timestamp), "swap did not set configs[src][dst].zzz to block.timestamp";
    assert numOtherAfter == numOtherBefore, "swap did not keep unchanged the rest of configs[x][y].num";
    assert zzzOtherAfter == zzzOtherBefore, "swap did not keep unchanged the rest of configs[x][y].zzz";
    assert swapCounter == swapCounterBefore + 1, "swap did not execute exactly one swap external call";
    assert swapAddr == swapper(), "swap did not execute the swap external call to the correct 'swapper()' contract";
    assert swapSrc == src, "swap did not not pass the correct src to the external call";
    assert swapDst == dst, "swap did not not pass the correct dst to the external call";
    assert to_mathint(swapLot) == lotSrcDst, "swap did not not pass the correct lot to the external call";
    assert to_mathint(swapMinOut) == (minOut == 0 ? reqSrcDst : to_mathint(minOut)), "swap did not not pass the correct minOut to the external call";
    assert swapCallee == callee, "swap did not not pass the correct callee to the external call";
    assert swapDataLength == data.length, "swap did not not pass the correct data to the external call";
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

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5, "Revert rules failed";
}
