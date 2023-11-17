// VaultMinter.spec

methods {
    function wards(address) external returns (uint256) envfree;
    function buds(address) external returns (uint256) envfree;
    function config() external returns (int64, uint32, uint32, uint128) envfree;
    function vault() external returns (address) envfree;
    function _.draw(uint256 wad) external => drawSummary(calledContract, wad) expect bool; // Forcing to have a return value
    function _.wipe(uint256 wad) external => wipeSummary(calledContract, wad) expect bool; // Forcing to have a return value
}

ghost mapping(address => bool) nonZeroExtcodesize;
hook EXTCODESIZE(address addr) uint v {
    nonZeroExtcodesize[addr] = (v != 0);
}

ghost mathint drawCounter;
ghost address drawAddr;
ghost uint256 drawAmount;
function drawSummary(address addr, uint256 amount) returns bool {
    drawCounter = drawCounter + 1;
    drawAddr = addr;
    drawAmount = amount;
    return true;
}

ghost mathint wipeCounter;
ghost address wipeAddr;
ghost uint256 wipeAmount;
function wipeSummary(address addr, uint256 amount) returns bool {
    wipeCounter = wipeCounter + 1;
    wipeAddr = addr;
    wipeAmount = amount;
    return true;
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    mathint budsBefore = buds(anyAddr);
    mathint numBefore; mathint hopBefore; mathint zzzBefore; mathint lotBefore;
    numBefore, hopBefore, zzzBefore, lotBefore = config();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint budsAfter = buds(anyAddr);
    mathint numAfter; mathint hopAfter; mathint zzzAfter; mathint lotAfter;
    numAfter, hopAfter, zzzAfter, lotAfter = config();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "wards[x] changed in an unexpected function";
    assert budsAfter != budsBefore => f.selector == sig:kiss(address).selector || f.selector == sig:diss(address).selector, "buds[x] changed in an unexpected function";
    assert numAfter != numBefore => f.selector == sig:setConfig(int64,uint32,uint128).selector || f.selector == sig:draw().selector || f.selector == sig:wipe().selector, "config.num changed in an unexpected function";
    assert hopAfter != hopBefore => f.selector == sig:setConfig(int64,uint32,uint128).selector, "config.hop changed in an unexpected function";
    assert zzzAfter != zzzBefore => f.selector == sig:setConfig(int64,uint32,uint128).selector || f.selector == sig:draw().selector || f.selector == sig:wipe().selector, "config.zzz changed in an unexpected function";
    assert lotAfter != lotBefore => f.selector == sig:setConfig(int64,uint32,uint128).selector, "config.lot changed in an unexpected function";
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
rule setConfig(int64 num, uint32 hop, uint128 lot) {
    env e;

    setConfig(e, num, hop, lot);

    mathint numAfter; mathint hopAfter; mathint zzzAfter; mathint lotAfter;
    numAfter, hopAfter, zzzAfter, lotAfter = config();

    assert numAfter == to_mathint(num), "setConfig did not set config.num to num";
    assert hopAfter == to_mathint(hop), "setConfig did not set config.hop to hop";
    assert zzzAfter == 0, "setConfig did not set config.zzz to 0";
    assert lotAfter == to_mathint(lot), "setConfig did not set config.lot to lot";
}

// Verify revert rules on setConfig
rule setConfig_revert(int64 num, uint32 hop, uint128 lot) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    setConfig@withrevert(e, num, hop, lot);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting draw
rule draw() {
    env e;

    require e.block.timestamp <= max_uint32;

    address vault = vault();

    mathint a; mathint b;

    mathint numBefore; mathint lot;
    numBefore, a, b, lot = config();

    mathint drawAmountBefore = drawAmount;
    mathint drawCounterBefore = drawCounter;

    draw(e);

    mathint numAfter; mathint zzzAfter;
    numAfter, a, zzzAfter, a = config();

    assert numAfter == numBefore - 1, "draw did not decrease config.num by 1";
    assert zzzAfter == to_mathint(e.block.timestamp), "draw did not set config.zzz to block.timestamp";
    assert drawCounter == drawCounterBefore + 1, "draw did not execute exactly one draw external call";
    assert drawAddr == vault, "draw did not execute the draw external call to the correct vault contract";
    assert to_mathint(drawAmount) == lot, "draw did not pass the correct amount to the draw external call";
}

// Verify revert rules on draw
rule draw_revert() {
    env e;

    address vault = vault();

    require e.block.timestamp <= max_uint32;
    require !nonZeroExtcodesize[vault];

    mathint budsSender = buds(e.msg.sender);
    mathint a;
    mathint num; mathint hop; mathint zzz;
    num, hop, zzz, a = config();

    draw@withrevert(e);

    bool revert1 = e.msg.value > 0;
    bool revert2 = budsSender != 1;
    bool revert3 = num == 0;
    bool revert4 = to_mathint(e.block.timestamp) < zzz + hop;
    bool revert5 = !nonZeroExtcodesize[vault];

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5, "Revert rules failed";
}

// Verify correct storage changes for non reverting wipe
rule wipe() {
    env e;

    require e.block.timestamp <= max_uint32;

    address vault = vault();

    mathint a; mathint b;

    mathint numBefore; mathint lot;
    numBefore, a, b, lot = config();

    mathint wipeCounterBefore = wipeCounter;

    wipe(e);

    mathint numAfter; mathint zzzAfter;
    numAfter, a, zzzAfter, a = config();

    assert numAfter == numBefore + 1, "wipe did not decrease config.num by 1";
    assert zzzAfter == to_mathint(e.block.timestamp), "wipe did not set config.zzz to block.timestamp";
    assert wipeCounter == wipeCounterBefore + 1, "wipe did not execute exactly one wipe external call";
    assert wipeAddr == vault, "wipe did not execute the wipe external call to the correct vault contract";
    assert to_mathint(wipeAmount) == lot, "wipe did not pass the correct amount to the wipe external call";
}

// Verify revert rules on wipe
rule wipe_revert() {
    env e;

    address vault = vault();

    require e.block.timestamp <= max_uint32;
    require !nonZeroExtcodesize[vault];

    mathint budsSender = buds(e.msg.sender);
    mathint a;
    mathint num; mathint hop; mathint zzz;
    num, hop, zzz, a = config();

    wipe@withrevert(e);

    bool revert1 = e.msg.value > 0;
    bool revert2 = budsSender != 1;
    bool revert3 = num == 0;
    bool revert4 = to_mathint(e.block.timestamp) < zzz + hop;
    bool revert5 = !nonZeroExtcodesize[vault];

    assert lastReverted <=> revert1 || revert2 || revert3 ||
                            revert4 || revert5, "Revert rules failed";
}
