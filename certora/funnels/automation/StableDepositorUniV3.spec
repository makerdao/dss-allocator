// StableDepositorUniV3.spec

methods {
    function wards(address) external returns (uint256) envfree;
    function buds(address) external returns (uint256) envfree;
    function configs(address, address, uint24, int24, int24) external returns (int32, uint32, uint96, uint96, uint96, uint96, uint32) envfree;
    function _.deposit(DepositorUniV3Like.LiquidityParams p) external => depositSummary(p) expect uint128, uint256, uint256;
    function _.withdraw(DepositorUniV3Like.LiquidityParams p, bool takeFees) external => withdrawSummary(p, takeFees) expect uint128, uint256, uint256, uint256, uint256;
    function _.collect(DepositorUniV3Like.CollectParams p) external => collectSummary(p) expect uint256, uint256;
}

ghost uint128 retValue;
ghost uint256 retValue2;
ghost uint256 retValue3;
ghost uint256 retValue4;
ghost uint256 retValue5;

ghost address depositGem0;
ghost address depositGem1;
ghost uint24  depositFee;
ghost int24   depositTickLower;
ghost int24   depositTickUpper;
ghost uint128 depositLiquidity;
ghost uint256 depositAmt0Desired;
ghost uint256 depositAmt1Desired;
ghost uint256 depositAmt0Min;
ghost uint256 depositAmt1Min;
function depositSummary(DepositorUniV3Like.LiquidityParams p) returns (uint128, uint256, uint256) {
    depositGem0 = p.gem0;
    depositGem1 = p.gem1;
    depositFee = p.fee;
    depositTickLower = p.tickLower;
    depositTickUpper = p.tickUpper;
    depositLiquidity = p.liquidity;
    depositAmt0Desired = p.amt0Desired;
    depositAmt1Desired = p.amt1Desired;
    depositAmt0Min = p.amt0Min;
    depositAmt1Min = p.amt1Min;
    return (retValue, retValue2, retValue3);
}

ghost address withdrawGem0;
ghost address withdrawGem1;
ghost uint24  withdrawFee;
ghost int24   withdrawTickLower;
ghost int24   withdrawTickUpper;
ghost uint128 withdrawLiquidity;
ghost uint256 withdrawAmt0Desired;
ghost uint256 withdrawAmt1Desired;
ghost uint256 withdrawAmt0Min;
ghost uint256 withdrawAmt1Min;
ghost bool    withdrawTakeFees;
function withdrawSummary(DepositorUniV3Like.LiquidityParams p, bool takeFees) returns (uint128, uint256, uint256, uint256, uint256) {
    withdrawGem0 = p.gem0;
    withdrawGem1 = p.gem1;
    withdrawFee = p.fee;
    withdrawTickLower = p.tickLower;
    withdrawTickUpper = p.tickUpper;
    withdrawLiquidity = p.liquidity;
    withdrawAmt0Desired = p.amt0Desired;
    withdrawAmt1Desired = p.amt1Desired;
    withdrawAmt0Min = p.amt0Min;
    withdrawAmt1Min = p.amt1Min;
    withdrawTakeFees = takeFees;
    return (retValue, retValue2, retValue3, retValue4, retValue5);
}

ghost address collectGem0;
ghost address collectGem1;
ghost uint24  collectFee;
ghost int24   collectTickLower;
ghost int24   collectTickUpper;
function collectSummary(DepositorUniV3Like.CollectParams p) returns (uint256, uint256) {
    collectGem0 = p.gem0;
    collectGem1 = p.gem1;
    collectFee = p.fee;
    collectTickLower = p.tickLower;
    collectTickUpper = p.tickUpper;
    return (retValue2, retValue3);
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;
    address anyAddr;
    address anyAddr_2;
    uint24 anyUint24;
    int24 anyInt24;
    int24 anyInt24_2;

    mathint wardsOtherBefore = wards(other);
    mathint budsBefore = buds(anyAddr);
    mathint numBefore; mathint zzzBefore; mathint amt0Before; mathint amt1Before; mathint req0Before; mathint req1Before; mathint hopBefore;
    numBefore, zzzBefore, amt0Before, amt1Before, req0Before, req1Before, hopBefore = configs(anyAddr, anyAddr_2, anyUint24, anyInt24, anyInt24_2);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint budsAfter = buds(anyAddr);
    mathint numAfter; mathint zzzAfter; mathint amt0After; mathint amt1After; mathint req0After; mathint req1After; mathint hopAfter;
    numAfter, zzzAfter, amt0After, amt1After, req0After, req1After, hopAfter = configs(anyAddr, anyAddr_2, anyUint24, anyInt24, anyInt24_2);

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
    address anyAddr_2;
    uint24 anyUint24;
    int24 anyInt24;
    int24 anyInt24_2;

    mathint wardsOtherBefore = wards(other);
    mathint budsBefore = buds(anyAddr);
    mathint numBefore; mathint zzzBefore; mathint amt0Before; mathint amt1Before; mathint req0Before; mathint req1Before; mathint hopBefore;
    numBefore, zzzBefore, amt0Before, amt1Before, req0Before, req1Before, hopBefore = configs(anyAddr, anyAddr_2, anyUint24, anyInt24, anyInt24_2);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint budsAfter = buds(anyAddr);
    mathint numAfter; mathint zzzAfter; mathint amt0After; mathint amt1After; mathint req0After; mathint req1After; mathint hopAfter;
    numAfter, zzzAfter, amt0After, amt1After, req0After, req1After, hopAfter = configs(anyAddr, anyAddr_2, anyUint24, anyInt24, anyInt24_2);

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
    address anyAddr_2;
    uint24 anyUint24;
    int24 anyInt24;
    int24 anyInt24_2;

    mathint wardsBefore = wards(anyAddr);
    mathint budsOtherBefore = buds(other);
    mathint numBefore; mathint zzzBefore; mathint amt0Before; mathint amt1Before; mathint req0Before; mathint req1Before; mathint hopBefore;
    numBefore, zzzBefore, amt0Before, amt1Before, req0Before, req1Before, hopBefore = configs(anyAddr, anyAddr_2, anyUint24, anyInt24, anyInt24_2);

    kiss(e, usr);

    mathint wardsAfter = wards(anyAddr);
    mathint budsUsrAfter = buds(usr);
    mathint budsOtherAfter = buds(other);
    mathint numAfter; mathint zzzAfter; mathint amt0After; mathint amt1After; mathint req0After; mathint req1After; mathint hopAfter;
    numAfter, zzzAfter, amt0After, amt1After, req0After, req1After, hopAfter = configs(anyAddr, anyAddr_2, anyUint24, anyInt24, anyInt24_2);

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
    address anyAddr_2;
    uint24 anyUint24;
    int24 anyInt24;
    int24 anyInt24_2;

    mathint wardsBefore = wards(anyAddr);
    mathint budsOtherBefore = buds(other);
    mathint numBefore; mathint zzzBefore; mathint amt0Before; mathint amt1Before; mathint req0Before; mathint req1Before; mathint hopBefore;
    numBefore, zzzBefore, amt0Before, amt1Before, req0Before, req1Before, hopBefore = configs(anyAddr, anyAddr_2, anyUint24, anyInt24, anyInt24_2);

    diss(e, usr);

    mathint wardsAfter = wards(anyAddr);
    mathint budsUsrAfter = buds(usr);
    mathint budsOtherAfter = buds(other);
    mathint numAfter; mathint zzzAfter; mathint amt0After; mathint amt1After; mathint req0After; mathint req1After; mathint hopAfter;
    numAfter, zzzAfter, amt0After, amt1After, req0After, req1After, hopAfter = configs(anyAddr, anyAddr_2, anyUint24, anyInt24, anyInt24_2);

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

// Verify correct storage changes for non reverting deposit
rule deposit(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min) {
    env e;

    address anyAddr;
    address otherAddr;
    address otherAddr2;
    uint24 otherUint24;
    int24 otherInt24;
    int24 otherInt242;
    require otherAddr != gem0 || otherAddr2 != gem1 || fee != otherUint24 || tickLower != otherInt24 || tickUpper != otherInt242;

    require e.block.timestamp <= max_uint32;

    mathint wardsBefore = wards(anyAddr);
    mathint budsBefore = buds(anyAddr);
    mathint numGem0Gem1Before; mathint zzzGem0Gem1Before; mathint amt0Gem0Gem1Before; mathint amt1Gem0Gem1Before; mathint req0Gem0Gem1Before; mathint req1Gem0Gem1Before; mathint hopGem0Gem1Before;
    numGem0Gem1Before, zzzGem0Gem1Before, amt0Gem0Gem1Before, amt1Gem0Gem1Before, req0Gem0Gem1Before, req1Gem0Gem1Before, hopGem0Gem1Before = configs(gem0, gem1, fee, tickLower, tickUpper);
    mathint numOtherBefore; mathint zzzOtherBefore; mathint amt0OtherBefore; mathint amt1OtherBefore; mathint req0OtherBefore; mathint req1OtherBefore; mathint hopOtherBefore;
    numOtherBefore, zzzOtherBefore, amt0OtherBefore, amt1OtherBefore, req0OtherBefore, req1OtherBefore, hopOtherBefore = configs(otherAddr, otherAddr2, otherUint24, otherInt24, otherInt242);

    deposit(e, gem0, gem1, fee, tickLower, tickUpper, amt0Min, amt1Min);

    mathint wardsAfter = wards(anyAddr);
    mathint budsAfter = buds(anyAddr);
    mathint numGem0Gem1After; mathint zzzGem0Gem1After; mathint amt0Gem0Gem1After; mathint amt1Gem0Gem1After; mathint req0Gem0Gem1After; mathint req1Gem0Gem1After; mathint hopGem0Gem1After;
    numGem0Gem1After, zzzGem0Gem1After, amt0Gem0Gem1After, amt1Gem0Gem1After, req0Gem0Gem1After, req1Gem0Gem1After, hopGem0Gem1After = configs(gem0, gem1, fee, tickLower, tickUpper);
    mathint numOtherAfter; mathint zzzOtherAfter; mathint amt0OtherAfter; mathint amt1OtherAfter; mathint req0OtherAfter; mathint req1OtherAfter; mathint hopOtherAfter;
    numOtherAfter, zzzOtherAfter, amt0OtherAfter, amt1OtherAfter, req0OtherAfter, req1OtherAfter, hopOtherAfter = configs(otherAddr, otherAddr2, otherUint24, otherInt24, otherInt242);

    assert wardsAfter == wardsBefore, "deposit did not keep unchanged every wards[x]";
    assert budsAfter == budsBefore, "deposit did not keep unchanged every buds[x]";
    assert numGem0Gem1After == numGem0Gem1Before - 1, "deposit did not decrease configs[gem0][gem1][fee][tickLower][tickUpper].num by 1";
    assert zzzGem0Gem1After == to_mathint(e.block.timestamp), "deposit did not set configs[gem0][gem1][fee][tickLower][tickUpper].zzz to block.timestamp";
    assert amt0Gem0Gem1After == amt0Gem0Gem1Before, "deposit did not keep unchanged configs[gem0][gem1][fee][tickLower][tickUpper].amt0";
    assert amt1Gem0Gem1After == amt1Gem0Gem1Before, "deposit did not keep unchanged configs[gem0][gem1][fee][tickLower][tickUpper].amt1";
    assert req0Gem0Gem1After == req0Gem0Gem1Before, "deposit did not keep unchanged configs[gem0][gem1][fee][tickLower][tickUpper].req0";
    assert req1Gem0Gem1After == req1Gem0Gem1Before, "deposit did not keep unchanged configs[gem0][gem1][fee][tickLower][tickUpper].req1";
    assert hopGem0Gem1After == hopGem0Gem1Before, "deposit did not keep unchanged configs[gem0][gem1][fee][tickLower][tickUpper].hop";
    assert numOtherAfter == numOtherBefore, "deposit did not keep unchanged the rest of configs[x][y][z][a][b].num";
    assert zzzOtherAfter == zzzOtherBefore, "deposit did not keep unchanged the rest of configs[x][y][z][a][b].zzz";
    assert amt0OtherAfter == amt0OtherBefore, "deposit did not keep unchanged the rest of configs[x][y][z][a][b].amt0";
    assert amt1OtherAfter == amt1OtherBefore, "deposit did not keep unchanged the rest of configs[x][y][z][a][b].amt1";
    assert req0OtherAfter == req0OtherBefore, "deposit did not keep unchanged the rest of configs[x][y][z][a][b].req0";
    assert req1OtherAfter == req1OtherBefore, "deposit did not keep unchanged the rest of configs[x][y][z][a][b].req1";
    assert hopOtherAfter == hopOtherBefore, "deposit did not keep unchanged the rest of configs[x][y][z][a][b].hop";
    assert depositGem0 == gem0, "deposit did not pass the correct gem0 to the external call";
    assert depositGem1 == gem1, "deposit did not pass the correct gem1 to the external call";
    assert depositFee == fee, "deposit did not pass the correct fee to the external call";
    assert depositTickLower == tickLower, "deposit did not pass the correct tickLower to the external call";
    assert depositTickUpper == tickUpper, "deposit did not pass the correct tickUpper to the external call";
    assert depositLiquidity == 0, "deposit did not pass the correct liquidity to the external call";
    assert to_mathint(depositAmt0Desired) == amt0Gem0Gem1Before, "deposit did not pass the correct amt0Desired to the external call";
    assert to_mathint(depositAmt1Desired) == amt1Gem0Gem1Before, "deposit did not pass the correct amt1Desired to the external call";
    assert to_mathint(depositAmt0Min) == (amt0Min == 0 ? req0Gem0Gem1Before : to_mathint(amt0Min)), "deposit did not pass the correct amt0Min to the external call";
    assert to_mathint(depositAmt1Min) == (amt1Min == 0 ? req1Gem0Gem1Before : to_mathint(amt1Min)), "deposit did not pass the correct amt1Min to the external call";
}

// Verify revert rules on deposit
rule deposit_revert(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min) {
    env e;

    require e.block.timestamp <= max_uint32;

    mathint budsSender = buds(e.msg.sender);
    mathint numGem0Gem1; mathint zzzGem0Gem1; mathint amt0Gem0Gem1; mathint amt1Gem0Gem1; mathint req0Gem0Gem1; mathint req1Gem0Gem1; mathint hopGem0Gem1;
    numGem0Gem1, zzzGem0Gem1, amt0Gem0Gem1, amt1Gem0Gem1, req0Gem0Gem1, req1Gem0Gem1, hopGem0Gem1 = configs(gem0, gem1, fee, tickLower, tickUpper);

    deposit@withrevert(e, gem0, gem1, fee, tickLower, tickUpper, amt0Min, amt1Min);

    bool revert1 = e.msg.value > 0;
    bool revert2 = budsSender != 1;
    bool revert3 = numGem0Gem1 <= 0;
    bool revert4 = to_mathint(e.block.timestamp) < zzzGem0Gem1 + hopGem0Gem1;
    bool revert5 = to_mathint(amt0Min) > 0 && to_mathint(amt0Min) < req0Gem0Gem1;
    bool revert6 = to_mathint(amt1Min) > 0 && to_mathint(amt1Min) < req1Gem0Gem1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert revert6 => lastReverted, "revert6 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting withdraw
rule withdraw(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min) {
    env e;

    address anyAddr;
    address otherAddr;
    address otherAddr2;
    uint24 otherUint24;
    int24 otherInt24;
    int24 otherInt242;
    require otherAddr != gem0 || otherAddr2 != gem1 || fee != otherUint24 || tickLower != otherInt24 || tickUpper != otherInt242;

    require e.block.timestamp <= max_uint32;

    mathint wardsBefore = wards(anyAddr);
    mathint budsBefore = buds(anyAddr);
    mathint numGem0Gem1Before; mathint zzzGem0Gem1Before; mathint amt0Gem0Gem1Before; mathint amt1Gem0Gem1Before; mathint req0Gem0Gem1Before; mathint req1Gem0Gem1Before; mathint hopGem0Gem1Before;
    numGem0Gem1Before, zzzGem0Gem1Before, amt0Gem0Gem1Before, amt1Gem0Gem1Before, req0Gem0Gem1Before, req1Gem0Gem1Before, hopGem0Gem1Before = configs(gem0, gem1, fee, tickLower, tickUpper);
    mathint numOtherBefore; mathint zzzOtherBefore; mathint amt0OtherBefore; mathint amt1OtherBefore; mathint req0OtherBefore; mathint req1OtherBefore; mathint hopOtherBefore;
    numOtherBefore, zzzOtherBefore, amt0OtherBefore, amt1OtherBefore, req0OtherBefore, req1OtherBefore, hopOtherBefore = configs(otherAddr, otherAddr2, otherUint24, otherInt24, otherInt242);

    withdraw(e, gem0, gem1, fee, tickLower, tickUpper, amt0Min, amt1Min);

    mathint wardsAfter = wards(anyAddr);
    mathint budsAfter = buds(anyAddr);
    mathint numGem0Gem1After; mathint zzzGem0Gem1After; mathint amt0Gem0Gem1After; mathint amt1Gem0Gem1After; mathint req0Gem0Gem1After; mathint req1Gem0Gem1After; mathint hopGem0Gem1After;
    numGem0Gem1After, zzzGem0Gem1After, amt0Gem0Gem1After, amt1Gem0Gem1After, req0Gem0Gem1After, req1Gem0Gem1After, hopGem0Gem1After = configs(gem0, gem1, fee, tickLower, tickUpper);
    mathint numOtherAfter; mathint zzzOtherAfter; mathint amt0OtherAfter; mathint amt1OtherAfter; mathint req0OtherAfter; mathint req1OtherAfter; mathint hopOtherAfter;
    numOtherAfter, zzzOtherAfter, amt0OtherAfter, amt1OtherAfter, req0OtherAfter, req1OtherAfter, hopOtherAfter = configs(otherAddr, otherAddr2, otherUint24, otherInt24, otherInt242);

    assert wardsAfter == wardsBefore, "withdraw did not keep unchanged every wards[x]";
    assert budsAfter == budsBefore, "withdraw did not keep unchanged every buds[x]";
    assert numGem0Gem1After == numGem0Gem1Before + 1, "withdraw did not increase configs[gem0][gem1][fee][tickLower][tickUpper].num by 1";
    assert zzzGem0Gem1After == to_mathint(e.block.timestamp), "withdraw did not set configs[gem0][gem1][fee][tickLower][tickUpper].zzz to block.timestamp";
    assert amt0Gem0Gem1After == amt0Gem0Gem1Before, "withdraw did not keep unchanged configs[gem0][gem1][fee][tickLower][tickUpper].amt0";
    assert amt1Gem0Gem1After == amt1Gem0Gem1Before, "withdraw did not keep unchanged configs[gem0][gem1][fee][tickLower][tickUpper].amt1";
    assert req0Gem0Gem1After == req0Gem0Gem1Before, "withdraw did not keep unchanged configs[gem0][gem1][fee][tickLower][tickUpper].req0";
    assert req1Gem0Gem1After == req1Gem0Gem1Before, "withdraw did not keep unchanged configs[gem0][gem1][fee][tickLower][tickUpper].req1";
    assert hopGem0Gem1After == hopGem0Gem1Before, "withdraw did not keep unchanged configs[gem0][gem1][fee][tickLower][tickUpper].hop";
    assert numOtherAfter == numOtherBefore, "withdraw did not keep unchanged the rest of configs[x][y][z][a][b].num";
    assert zzzOtherAfter == zzzOtherBefore, "withdraw did not keep unchanged the rest of configs[x][y][z][a][b].zzz";
    assert amt0OtherAfter == amt0OtherBefore, "withdraw did not keep unchanged the rest of configs[x][y][z][a][b].amt0";
    assert amt1OtherAfter == amt1OtherBefore, "withdraw did not keep unchanged the rest of configs[x][y][z][a][b].amt1";
    assert req0OtherAfter == req0OtherBefore, "withdraw did not keep unchanged the rest of configs[x][y][z][a][b].req0";
    assert req1OtherAfter == req1OtherBefore, "withdraw did not keep unchanged the rest of configs[x][y][z][a][b].req1";
    assert hopOtherAfter == hopOtherBefore, "withdraw did not keep unchanged the rest of configs[x][y][z][a][b].hop";
    assert withdrawGem0 == gem0, "withdraw did not pass the correct gem0 to the external call";
    assert withdrawGem1 == gem1, "withdraw did not pass the correct gem1 to the external call";
    assert withdrawFee == fee, "withdraw did not pass the correct fee to the external call";
    assert withdrawTickLower == tickLower, "withdraw did not pass the correct tickLower to the external call";
    assert withdrawTickUpper == tickUpper, "withdraw did not pass the correct tickUpper to the external call";
    assert withdrawLiquidity == 0, "withdraw did not pass the correct liquidity to the external call";
    assert to_mathint(withdrawAmt0Desired) == amt0Gem0Gem1Before, "withdraw did not pass the correct amt0Desired to the external call";
    assert to_mathint(withdrawAmt1Desired) == amt1Gem0Gem1Before, "withdraw did not pass the correct amt1Desired to the external call";
    assert to_mathint(withdrawAmt0Min) == (amt0Min == 0 ? req0Gem0Gem1Before : to_mathint(amt0Min)), "withdraw did not pass the correct amt0Min to the external call";
    assert to_mathint(withdrawAmt1Min) == (amt1Min == 0 ? req1Gem0Gem1Before : to_mathint(amt1Min)), "withdraw did not pass the correct amt1Min to the external call";
    assert withdrawTakeFees, "withdraw did not pass the correct takeFees to the external call";
}

// Verify revert rules on withdraw
rule withdraw_revert(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min) {
    env e;

    require e.block.timestamp <= max_uint32;

    mathint budsSender = buds(e.msg.sender);
    mathint numGem0Gem1; mathint zzzGem0Gem1; mathint amt0Gem0Gem1; mathint amt1Gem0Gem1; mathint req0Gem0Gem1; mathint req1Gem0Gem1; mathint hopGem0Gem1;
    numGem0Gem1, zzzGem0Gem1, amt0Gem0Gem1, amt1Gem0Gem1, req0Gem0Gem1, req1Gem0Gem1, hopGem0Gem1 = configs(gem0, gem1, fee, tickLower, tickUpper);

    withdraw@withrevert(e, gem0, gem1, fee, tickLower, tickUpper, amt0Min, amt1Min);

    bool revert1 = e.msg.value > 0;
    bool revert2 = budsSender != 1;
    bool revert3 = numGem0Gem1 >= 0;
    bool revert4 = to_mathint(e.block.timestamp) < zzzGem0Gem1 + hopGem0Gem1;
    bool revert5 = to_mathint(amt0Min) > 0 && to_mathint(amt0Min) < req0Gem0Gem1;
    bool revert6 = to_mathint(amt1Min) > 0 && to_mathint(amt1Min) < req1Gem0Gem1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert revert6 => lastReverted, "revert6 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting collect
rule collect(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper) {
    env e;

    address anyAddr;
    address otherAddr;
    address otherAddr2;
    uint24 otherUint24;
    int24 otherInt24;
    int24 otherInt242;
    require otherAddr != gem0 || otherAddr2 != gem1 || fee != otherUint24 || tickLower != otherInt24 || tickUpper != otherInt242;

    require e.block.timestamp <= max_uint32;

    mathint wardsBefore = wards(anyAddr);
    mathint budsBefore = buds(anyAddr);
    mathint numBefore; mathint zzzBefore; mathint amt0Before; mathint amt1Before; mathint req0Before; mathint req1Before; mathint hopBefore;
    numBefore, zzzBefore, amt0Before, amt1Before, req0Before, req1Before, hopBefore = configs(otherAddr, otherAddr2, otherUint24, otherInt24, otherInt242);

    collect(e, gem0, gem1, fee, tickLower, tickUpper);

    mathint wardsAfter = wards(anyAddr);
    mathint budsAfter = buds(anyAddr);
    mathint numAfter; mathint zzzAfter; mathint amt0After; mathint amt1After; mathint req0After; mathint req1After; mathint hopAfter;
    numAfter, zzzAfter, amt0After, amt1After, req0After, req1After, hopAfter = configs(otherAddr, otherAddr2, otherUint24, otherInt24, otherInt242);

    assert wardsAfter == wardsBefore, "collect did not keep unchanged every wards[x]";
    assert budsAfter == budsBefore, "collect did not keep unchanged every buds[x]";
    assert numAfter == numBefore, "collect did not keep unchanged every configs[x][y][z][a][b].num";
    assert zzzAfter == zzzBefore, "collect did not keep unchanged every configs[x][y][z][a][b].zzz";
    assert amt0After == amt0Before, "collect did not keep unchanged every configs[x][y][z][a][b].amt0";
    assert amt1After == amt1Before, "collect did not keep unchanged every configs[x][y][z][a][b].amt1";
    assert req0After == req0Before, "collect did not keep unchanged every configs[x][y][z][a][b].req0";
    assert req1After == req1Before, "collect did not keep unchanged every configs[x][y][z][a][b].req1";
    assert hopAfter == hopBefore, "collect did not keep unchanged every configs[x][y][z][a][b].hop";
    assert collectGem0 == gem0, "collect did not pass the correct gem0 to the external call";
    assert collectGem1 == gem1, "collect did not pass the correct gem1 to the external call";
    assert collectFee == fee, "collect did not pass the correct fee to the external call";
    assert collectTickLower == tickLower, "collect did not pass the correct tickLower to the external call";
    assert collectTickUpper == tickUpper, "collect did not pass the correct tickUpper to the external call";
}

// Verify revert rules on collect
rule collect_revert(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper) {
    env e;

    mathint budsSender = buds(e.msg.sender);

    collect@withrevert(e, gem0, gem1, fee, tickLower, tickUpper);

    bool revert1 = e.msg.value > 0;
    bool revert2 = budsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}
