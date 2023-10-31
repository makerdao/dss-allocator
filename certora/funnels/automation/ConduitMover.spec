// ConduitMover.spec

methods {
    function wards(address) external returns (uint256) envfree;
    function buds(address) external returns (uint256) envfree;
    function configs(address, address, address) external returns (uint64, uint32, uint32, uint128) envfree;
    function ilk() external returns (bytes32) envfree;
    function buffer() external returns (address) envfree;
    function _.withdraw(bytes32 ilk, address gem, uint256 amount) external => withdrawSummary(calledContract, ilk, gem, amount) expect uint256;
    function _.deposit(bytes32 ilk, address gem, uint256 amount) external => depositSummary(calledContract, ilk, gem, amount) expect bool; // Forcing to have a return value
}

ghost mapping(address => bool) nonZeroExtcodesize;
hook EXTCODESIZE(address addr) uint v {
    nonZeroExtcodesize[addr] = (v != 0);
}

ghost mathint withdrawCounter;
ghost address withdrawAddr;
ghost bytes32 withdrawIlk;
ghost address withdrawGem;
ghost uint256 withdrawAmount;
ghost uint256 withdrawReturn;
function withdrawSummary(address addr, bytes32 ilk, address gem, uint256 amount) returns uint256 {
    withdrawCounter = withdrawCounter + 1;
    withdrawAddr = addr;
    withdrawIlk = ilk;
    withdrawGem = gem;
    withdrawAmount = amount;
    return withdrawReturn;
}

ghost mathint depositCounter;
ghost address depositAddr;
ghost bytes32 depositIlk;
ghost address depositGem;
ghost uint256 depositAmount;
function depositSummary(address addr, bytes32 ilk, address gem, uint256 amount) returns bool {
    depositCounter = depositCounter + 1;
    depositAddr = addr;
    depositIlk = ilk;
    depositGem = gem;
    depositAmount = amount;
    return true;
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;
    address anyAddr_2;
    address anyAddr_3;

    mathint wardsBefore = wards(anyAddr);
    mathint budsBefore = buds(anyAddr);
    mathint numBefore; mathint hopBefore; mathint zzzBefore; mathint lotBefore;
    numBefore, hopBefore, zzzBefore, lotBefore = configs(anyAddr, anyAddr_2, anyAddr_3);

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint budsAfter = buds(anyAddr);
    mathint numAfter; mathint hopAfter; mathint zzzAfter; mathint lotAfter;
    numAfter, hopAfter, zzzAfter, lotAfter = configs(anyAddr, anyAddr_2, anyAddr_3);

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "wards[x] changed in an unexpected function";
    assert budsAfter != budsBefore => f.selector == sig:kiss(address).selector || f.selector == sig:diss(address).selector, "buds[x] changed in an unexpected function";
    assert numAfter != numBefore => f.selector == sig:setConfig(address,address,address,uint64,uint32,uint128).selector || f.selector == sig:move(address,address,address).selector, "configs[x][y][z].num changed in an unexpected function";
    assert hopAfter != hopBefore => f.selector == sig:setConfig(address,address,address,uint64,uint32,uint128).selector, "configs[x][y][z].hop changed in an unexpected function";
    assert zzzAfter != zzzBefore => f.selector == sig:setConfig(address,address,address,uint64,uint32,uint128).selector || f.selector == sig:move(address,address,address).selector, "configs[x][y][z].zzz changed in an unexpected function";
    assert lotAfter != lotBefore => f.selector == sig:setConfig(address,address,address,uint64,uint32,uint128).selector, "configs[x][y][z].lot changed in an unexpected function";
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

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
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
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
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

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting setConfig
rule setConfig(address from, address to, address gem, uint64 num, uint32 hop, uint128 lot) {
    env e;

    address otherAddr;
    address otherAddr_2;
    address otherAddr_3;
    require otherAddr != from || otherAddr_2 != to || otherAddr_3 != gem;

    mathint numOtherBefore; mathint hopOtherBefore; mathint zzzOtherBefore; mathint lotOtherBefore;
    numOtherBefore, hopOtherBefore, zzzOtherBefore, lotOtherBefore = configs(otherAddr, otherAddr_2, otherAddr_3);

    setConfig(e, from, to, gem, num, hop, lot);

    mathint numFromToGemAfter; mathint hopFromToGemAfter; mathint zzzFromToGemAfter; mathint lotFromToGemAfter;
    numFromToGemAfter, hopFromToGemAfter, zzzFromToGemAfter, lotFromToGemAfter = configs(from, to, gem);
    mathint numOtherAfter; mathint hopOtherAfter; mathint zzzOtherAfter; mathint lotOtherAfter;
    numOtherAfter, hopOtherAfter, zzzOtherAfter, lotOtherAfter = configs(otherAddr, otherAddr_2, otherAddr_3);

    assert numFromToGemAfter == to_mathint(num), "setConfig did not set configs[from][to][gem].num to num";
    assert hopFromToGemAfter == to_mathint(hop), "setConfig did not set configs[from][to][gem].hop to hop";
    assert zzzFromToGemAfter == 0, "setConfig did not set configs[from][to][gem].zzz to 0";
    assert lotFromToGemAfter == to_mathint(lot), "setConfig did not set configs[from][to][gem].lot to lot";
    assert numOtherAfter == numOtherBefore, "setConfig did not keep unchanged the rest of configs[x][y][z].num";
    assert hopOtherAfter == hopOtherBefore, "setConfig did not keep unchanged the rest of configs[x][y][z].hop";
    assert zzzOtherAfter == zzzOtherBefore, "setConfig did not keep unchanged the rest of configs[x][y][z].zzz";
    assert lotOtherAfter == lotOtherBefore, "setConfig did not keep unchanged the rest of configs[x][y][z].lot";
}

// Verify revert rules on setConfig
rule setConfig_revert(address from, address to, address gem, uint64 num, uint32 hop, uint128 lot) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    setConfig@withrevert(e, from, to, gem, num, hop, lot);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting move
rule move(address from, address to, address gem) {
    env e;

    address otherAddr;
    address otherAddr_2;
    address otherAddr_3;
    require otherAddr != from || otherAddr_2 != to || otherAddr_3 != gem;

    require e.block.timestamp <= max_uint32;

    address buffer = buffer();

    mathint a; mathint b;

    mathint numFromToGemBefore; mathint lotFromToGem;
    numFromToGemBefore, a, b, lotFromToGem = configs(from, to, gem);
    mathint numOtherBefore; mathint zzzOtherBefore;
    numOtherBefore, a, zzzOtherBefore, b = configs(otherAddr, otherAddr_2, otherAddr_3);

    bytes32 withdrawIlkBefore = withdrawIlk;
    address withdrawGemBefore = withdrawGem;
    mathint withdrawAmountBefore = withdrawAmount;
    bytes32 depositIlkBefore = depositIlk;
    address depositGemBefore = depositGem;
    mathint depositAmountBefore = depositAmount;

    mathint withdrawCounterBefore = withdrawCounter;
    mathint depositCounterBefore = depositCounter;

    move(e, from, to, gem);

    mathint numFromToGemAfter; mathint zzzFromToGemAfter;
    numFromToGemAfter, a, zzzFromToGemAfter, b = configs(from, to, gem);
    mathint numOtherAfter; mathint zzzOtherAfter;
    numOtherAfter, a, zzzOtherAfter, b = configs(otherAddr, otherAddr_2, otherAddr_3);

    assert numFromToGemAfter == numFromToGemBefore - 1, "move did not decrease configs[from][to][gem].num by 1";
    assert zzzFromToGemAfter == to_mathint(e.block.timestamp), "move did not set configs[from][to][gem].zzz to block.timestamp";
    assert numOtherAfter == numOtherBefore, "move did not keep unchanged the rest of configs[x][y][z].num";
    assert zzzOtherAfter == zzzOtherBefore, "move did not keep unchanged the rest of configs[x][y][z].zzz";
    assert from != buffer => withdrawCounter == withdrawCounterBefore + 1, "move did not execute exactly one withdraw external call";
    assert from != buffer => withdrawAddr == from, "move did not execute the withdraw external call to the correct 'from' contract";
    assert from != buffer => withdrawIlk == ilk(), "move did not pass the correct ilk to the withdraw external call";
    assert from != buffer => withdrawGem == gem, "move did not pass the correct gen to the withdraw external call";
    assert from != buffer => to_mathint(withdrawAmount) == lotFromToGem, "move did not pass the correct amount to the withdraw external call";
    assert from == buffer => withdrawCounter == withdrawCounterBefore, "move did execute one or more withdraw external call when it did not correspond";
    assert from == buffer => withdrawIlk == withdrawIlkBefore, "move did execute the withdraw external call when it did not correspond";
    assert from == buffer => withdrawGem == withdrawGemBefore, "move did execute the withdraw external call when it did not correspond 2";
    assert from == buffer => to_mathint(withdrawAmount) == withdrawAmountBefore, "move did execute the withdraw external call when it did not correspond 3";
    assert to != buffer => depositCounter == depositCounterBefore + 1, "move did not execute exactly one deposit external call";
    assert to != buffer => depositAddr == to, "move did not execute the deposit external call to the correct 'to' contract";
    assert to != buffer => depositIlk == ilk(), "move did not pass the correct ilk to the deposit external call";
    assert to != buffer => depositGem == gem, "move did not pass the correct gen to the deposit external call";
    assert to != buffer => to_mathint(depositAmount) == lotFromToGem, "move did not pass the correct amount to the deposit external call";
    assert to == buffer => depositCounter == depositCounterBefore, "move did execute one or more deposit external call when it did not correspond";
    assert to == buffer => depositIlk == depositIlkBefore, "move did execute the deposit external call when it did not correspond";
    assert to == buffer => depositGem == depositGemBefore, "move did execute the deposit external call when it did not correspond 2";
    assert to == buffer => to_mathint(depositAmount) == depositAmountBefore, "move did execute the deposit external call when it did not correspond 3";
}

// Verify revert rules on move
rule move_revert(address from, address to, address gem) {
    env e;

    require e.block.timestamp <= max_uint32;
    require !nonZeroExtcodesize[to];

    address buffer = buffer();

    mathint budsSender = buds(e.msg.sender);
    mathint numFromToGem; mathint hopFromToGem; mathint zzzFromToGem; mathint lotFromToGem;
    numFromToGem, hopFromToGem, zzzFromToGem, lotFromToGem = configs(from, to, gem);

    require to_mathint(withdrawReturn) == lotFromToGem;

    move@withrevert(e, from, to, gem);

    bool revert1 = e.msg.value > 0;
    bool revert2 = budsSender != 1;
    bool revert3 = numFromToGem == 0;
    bool revert4 = to_mathint(e.block.timestamp) < zzzFromToGem + hopFromToGem;
    bool revert5 = to_mathint(withdrawReturn) != lotFromToGem;
    bool revert6 = to != buffer && !nonZeroExtcodesize[to];

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert revert6 => lastReverted, "revert6 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6, "Revert rules are not covering all the cases";
}
