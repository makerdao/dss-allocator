// DepositorUniV3.spec

using AllocatorRoles as roles;
using PoolUniV3Mock as poolCon;
using Gem0Mock as gem0Con;
using Gem1Mock as gem1Con;
using Auxiliar as aux;

methods {
    function ilk() external returns (bytes32) envfree;
    function buffer() external returns (address) envfree;
    function wards(address) external returns (uint256) envfree;
    function limits(address, address, uint24) external returns (uint96, uint96, uint32, uint96, uint96, uint32) envfree;
    function _getPool(address gem0, address gem1, uint24 fee) internal returns (address) => getPoolSummary(gem0, gem1, fee);
    function _getLiquidityForAmts(address pool, int24 tickLower, int24 tickUpper, uint256 amt0Desired, uint256 amt1Desired) internal returns (uint128) => getLiquidityForAmtsSummary(pool, tickLower, tickUpper, amt0Desired, amt1Desired);
    function getPosition(address, address, uint24, int24, int24) external returns (uint128, uint256, uint256, uint128, uint128) envfree;
    function roles.canCall(bytes32, address, address, bytes4) external returns (bool) envfree;
    function _.mint(address, int24, int24, uint128, bytes) external => DISPATCHER(true);
    function _.burn(int24, int24, uint128) external => DISPATCHER(true);
    function _.collect(address, int24, int24, uint128, uint128) external => DISPATCHER(true);
    function _.uniswapV3MintCallback(uint256, uint256, bytes) external => DISPATCHER(true);
    function poolCon.gem0() external returns (address) envfree;
    function poolCon.gem1() external returns (address) envfree;
    function poolCon.fee() external returns (uint24) envfree;
    function poolCon.random0() external returns (uint128) envfree;
    function poolCon.random1() external returns (uint128) envfree;
    function poolCon.random2() external returns (uint128) envfree;
    function poolCon.random3() external returns (uint128) envfree;
    function _.positions(bytes32) external => DISPATCHER(true);
    function gem0Con.balanceOf(address) external returns (uint256) envfree;
    function gem1Con.balanceOf(address) external returns (uint256) envfree;
    function gem0Con.allowance(address, address) external returns (uint256) envfree;
    function gem1Con.allowance(address, address) external returns (uint256) envfree;
    function aux.getHash(address, int24, int24) external returns (bytes32) envfree;
    function aux.decode(bytes) external returns (address, address, uint24) envfree;
    function _.transfer(address, uint256) external => DISPATCHER(true) UNRESOLVED;
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true) UNRESOLVED;
}

ghost mapping(address => mapping(int24 => mapping(int24 => mapping(uint256 => mapping(uint256 => uint128))))) _liquidityMap;

function getLiquidityForAmtsSummary(address pool, int24 tickLower, int24 tickUpper, uint256 amt0Desired, uint256 amt1Desired) returns uint128 {
    return _liquidityMap[pool][tickLower][tickUpper][amt0Desired][amt1Desired];
}

ghost mapping(address => mapping(address => mapping(uint24 => address))) _poolMap;

function getPoolSummary(address gem0, address gem1, uint24 fee) returns address {
    return _poolMap[gem0][gem1][fee];
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;
    address anyAddr;
    address anyAddr_2;
    uint24 anyUint24;

    mathint wardsOtherBefore = wards(other);
    mathint cap0Before; mathint cap1Before; mathint eraBefore; mathint due0Before; mathint due1Before; mathint endBefore;
    cap0Before, cap1Before, eraBefore, due0Before, due1Before, endBefore = limits(anyAddr, anyAddr_2, anyUint24);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint cap0After; mathint cap1After; mathint eraAfter; mathint due0After; mathint due1After; mathint endAfter;
    cap0After, cap1After, eraAfter, due0After, due1After, endAfter = limits(anyAddr, anyAddr_2, anyUint24);

    assert wardsUsrAfter == 1, "rely did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "rely did not keep unchanged the rest of wards[x]";
    assert cap0After == cap0Before, "rely did not keep unchanged every limits[x][y][z].cap0";
    assert cap1After == cap1Before, "rely did not keep unchanged every limits[x][y][z].cap1";
    assert eraAfter == eraBefore, "rely did not keep unchanged every limits[x][y][z].era";
    assert due0After == due0Before, "rely did not keep unchanged every limits[x][y][z].due0";
    assert due1After == due1Before, "rely did not keep unchanged every limits[x][y][z].due1";
    assert endAfter == endBefore, "rely did not keep unchanged every limits[x][y][z].end";
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
    address anyAddr;
    address anyAddr_2;
    uint24 anyUint24;

    mathint wardsOtherBefore = wards(other);
    mathint cap0Before; mathint cap1Before; mathint eraBefore; mathint due0Before; mathint due1Before; mathint endBefore;
    cap0Before, cap1Before, eraBefore, due0Before, due1Before, endBefore = limits(anyAddr, anyAddr_2, anyUint24);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint cap0After; mathint cap1After; mathint eraAfter; mathint due0After; mathint due1After; mathint endAfter;
    cap0After, cap1After, eraAfter, due0After, due1After, endAfter = limits(anyAddr, anyAddr_2, anyUint24);

    assert wardsUsrAfter == 0, "deny did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "deny did not keep unchanged the rest of wards[x]";
    assert cap0After == cap0Before, "deny did not keep unchanged every limits[x][y][z].cap0";
    assert cap1After == cap1Before, "deny did not keep unchanged every limits[x][y][z].cap1";
    assert eraAfter == eraBefore, "deny did not keep unchanged every limits[x][y][z].era";
    assert due0After == due0Before, "deny did not keep unchanged every limits[x][y][z].due0";
    assert due1After == due1Before, "deny did not keep unchanged every limits[x][y][z].due1";
    assert endAfter == endBefore, "deny did not keep unchanged every limits[x][y][z].end";
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

// Verify correct storage changes for non reverting setLimits
rule setLimits(address gem0, address gem1, uint24 fee, uint96 cap0, uint96 cap1, uint32 era) {
    env e;

    address anyAddr;
    address otherAddr;
    address otherAddr2;
    uint24 otherUint24;
    require otherAddr != gem0 || otherAddr2 != gem1 || otherUint24 != fee;

    mathint wardsBefore = wards(anyAddr);
    mathint cap0OtherBefore; mathint cap1OtherBefore; mathint eraOtherBefore; mathint due0OtherBefore; mathint due1OtherBefore; mathint endOtherBefore;
    cap0OtherBefore, cap1OtherBefore, eraOtherBefore, due0OtherBefore, due1OtherBefore, endOtherBefore = limits(otherAddr, otherAddr2, otherUint24);

    setLimits(e, gem0, gem1, fee, cap0, cap1, era);

    mathint wardsAfter = wards(anyAddr);
    mathint cap0Gem0Gem1FeeAfter; mathint cap1Gem0Gem1FeeAfter; mathint eraGem0Gem1FeeAfter; mathint due0Gem0Gem1FeeAfter; mathint due1Gem0Gem1FeeAfter; mathint endGem0Gem1FeeAfter;
    cap0Gem0Gem1FeeAfter, cap1Gem0Gem1FeeAfter, eraGem0Gem1FeeAfter, due0Gem0Gem1FeeAfter, due1Gem0Gem1FeeAfter, endGem0Gem1FeeAfter = limits(gem0, gem1, fee);
    mathint cap0OtherAfter; mathint cap1OtherAfter; mathint eraOtherAfter; mathint due0OtherAfter; mathint due1OtherAfter; mathint endOtherAfter;
    cap0OtherAfter, cap1OtherAfter, eraOtherAfter, due0OtherAfter, due1OtherAfter, endOtherAfter = limits(otherAddr, otherAddr2, otherUint24);

    assert wardsAfter == wardsBefore, "setLimits did not keep unchanged every wards[x]";
    assert cap0Gem0Gem1FeeAfter == to_mathint(cap0), "setLimits did not set limits[gem0][gem1][fee].cap0 to cap0";
    assert cap1Gem0Gem1FeeAfter == to_mathint(cap1), "setLimits did not set limits[gem0][gem1][fee].cap1 to cap1";
    assert eraGem0Gem1FeeAfter == to_mathint(era), "setLimits did not set limits[gem0][gem1][fee].era to era";
    assert due0Gem0Gem1FeeAfter == 0, "setLimits did not set limits[gem0][gem1][fee].due0 to 0";
    assert due1Gem0Gem1FeeAfter == 0, "setLimits did not set limits[gem0][gem1][fee].due1 to 0";
    assert endGem0Gem1FeeAfter == 0, "setLimits did not set limits[gem0][gem1][fee].end to 0";
    assert cap0OtherAfter == cap0OtherBefore, "setLimits did not keep unchanged the rest of limits[x][y][z].cap0";
    assert cap1OtherAfter == cap1OtherBefore, "setLimits did not keep unchanged the rest of limits[x][y][z].cap1";
    assert eraOtherAfter == eraOtherBefore, "setLimits did not keep unchanged the rest of limits[x][y][z].era";
    assert due0OtherAfter == due0OtherBefore, "setLimits did not keep unchanged the rest of limits[x][y][z].due0";
    assert due1OtherAfter == due1OtherBefore, "setLimits did not keep unchanged the rest of limits[x][y][z].due1";
    assert endOtherAfter == endOtherBefore, "setLimits did not keep unchanged the rest of limits[x][y][z].end";
}

// Verify revert rules on setLimits
rule setLimits_revert(address gem0, address gem1, uint24 fee, uint96 cap0, uint96 cap1, uint32 era) {
    env e;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0x222df168));
    mathint wardsSender = wards(e.msg.sender);

    setLimits@withrevert(e, gem0, gem1, fee, cap0, cap1, era);

    bool revert1 = e.msg.value > 0;
    bool revert2 = !canCall && wardsSender != 1;
    bool revert3 = gem0 >= gem1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases";
}

// Verify correct response from getPosition
rule getPosition(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper) {
    env e;

    bytes32 hashC = aux.getHash(currentContract, tickLower, tickUpper);
    mathint expLiquidity; mathint expFeeGrowthInside0LastX128; mathint expFeeGrowthInside1LastX128; mathint expTokensOwed0; mathint expTokensOwed1;
    expLiquidity, expFeeGrowthInside0LastX128, expFeeGrowthInside1LastX128, expTokensOwed0, expTokensOwed1 = poolCon.positions(e, hashC);

    mathint liquidity; mathint feeGrowthInside0LastX128; mathint feeGrowthInside1LastX128; mathint tokensOwed0; mathint tokensOwed1;
    liquidity, feeGrowthInside0LastX128, feeGrowthInside1LastX128, tokensOwed0, tokensOwed1 = getPosition(gem0, gem1, fee, tickLower, tickUpper);

    assert liquidity == expLiquidity, "getPosition did not return the expected liquidity value";
    assert feeGrowthInside0LastX128 == expFeeGrowthInside0LastX128, "getPosition did not return the expected feeGrowthInside0LastX128 value";
    assert feeGrowthInside1LastX128 == expFeeGrowthInside1LastX128, "getPosition did not return the expected feeGrowthInside1LastX128 value";
    assert tokensOwed0 == expTokensOwed0, "getPosition did not return the expected tokensOwed0 value";
    assert tokensOwed1 == expTokensOwed1, "getPosition did not return the expected tokensOwed1 value";
}

// Verify correct storage changes for non reverting uniswapV3MintCallback
rule uniswapV3MintCallback(uint256 amt0Owed, uint256 amt1Owed, bytes data) {
    env e;

    address gem0; address gem1; uint24 fee;
    gem0, gem1, fee = aux.decode(data);

    require gem0 == gem0Con;
    require gem1 == gem1Con;

    address anyAddr;
    address anyAddr_2;
    uint24 anyUint24;

    address buffer = buffer();
    require buffer != e.msg.sender;

    mathint wardsBefore = wards(anyAddr);
    mathint cap0Before; mathint cap1Before; mathint eraBefore; mathint due0Before; mathint due1Before; mathint endBefore;
    cap0Before, cap1Before, eraBefore, due0Before, due1Before, endBefore = limits(anyAddr, anyAddr_2, anyUint24);
    mathint gem0BalanceOfBufferBefore = gem0Con.balanceOf(buffer);
    mathint gem1BalanceOfBufferBefore = gem1Con.balanceOf(buffer);
    mathint gem0BalanceOfSenderBefore = gem0Con.balanceOf(e.msg.sender);
    mathint gem1BalanceOfSenderBefore = gem1Con.balanceOf(e.msg.sender);

    require gem0BalanceOfBufferBefore + gem0BalanceOfSenderBefore <= max_uint256;
    require gem1BalanceOfBufferBefore + gem1BalanceOfSenderBefore <= max_uint256;

    uniswapV3MintCallback(e, amt0Owed, amt1Owed, data);

    mathint wardsAfter = wards(anyAddr);
    mathint cap0After; mathint cap1After; mathint eraAfter; mathint due0After; mathint due1After; mathint endAfter;
    cap0After, cap1After, eraAfter, due0After, due1After, endAfter = limits(anyAddr, anyAddr_2, anyUint24);
    mathint gem0BalanceOfBufferAfter = gem0Con.balanceOf(buffer);
    mathint gem1BalanceOfBufferAfter = gem1Con.balanceOf(buffer);
    mathint gem0BalanceOfSenderAfter = gem0Con.balanceOf(e.msg.sender);
    mathint gem1BalanceOfSenderAfter = gem1Con.balanceOf(e.msg.sender);

    assert wardsAfter == wardsBefore, "uniswapV3MintCallback did not keep unchanged every wards[x]";
    assert cap0After == cap0Before, "uniswapV3MintCallback did not keep unchanged every limits[x][y][z].cap0";
    assert cap1After == cap1Before, "uniswapV3MintCallback did not keep unchanged every limits[x][y][z].cap1";
    assert eraAfter == eraBefore, "uniswapV3MintCallback did not keep unchanged every limits[x][y][z].era";
    assert due0After == due0Before, "uniswapV3MintCallback did not keep unchanged every limits[x][y][z].due0";
    assert due1After == due1Before, "uniswapV3MintCallback did not keep unchanged every limits[x][y][z].due1";
    assert endAfter == endBefore, "uniswapV3MintCallback did not keep unchanged every limits[x][y][z].end";
    assert gem0BalanceOfBufferAfter == gem0BalanceOfBufferBefore - amt0Owed, "uniswapV3MintCallback did not decrease gem0.balanceOf(buffer) by amt0Owed";
    assert gem1BalanceOfBufferAfter == gem1BalanceOfBufferBefore - amt1Owed, "uniswapV3MintCallback did not decrease gem1.balanceOf(buffer) by amt1Owed";
    assert gem0BalanceOfSenderAfter == gem0BalanceOfSenderBefore + amt0Owed, "uniswapV3MintCallback did not increase gem0.balanceOf(pool) by amt0Owed";
    assert gem1BalanceOfSenderAfter == gem1BalanceOfSenderBefore + amt1Owed, "uniswapV3MintCallback did not increase gem1.balanceOf(pool) by amt1Owed";
}

// Verify revert rules on uniswapV3MintCallback
rule uniswapV3MintCallback_revert(uint256 amt0Owed, uint256 amt1Owed, bytes data) {
    env e;

    address gem0; address gem1; uint24 fee;
    gem0, gem1, fee = aux.decode(data);

    require gem0 == gem0Con;
    require gem1 == gem1Con;

    address buffer = buffer();
    require buffer != currentContract;
    require buffer != e.msg.sender;

    address pool = getPoolSummary(gem0, gem1, fee);

    mathint gem0BalanceOfBuffer = gem0Con.balanceOf(buffer);
    mathint gem1BalanceOfBuffer = gem1Con.balanceOf(buffer);
    mathint gem0AllowanceBufferDepositor = gem0Con.allowance(buffer, currentContract);
    mathint gem1AllowanceBufferDepositor = gem1Con.allowance(buffer, currentContract);

    require gem0BalanceOfBuffer + gem0Con.balanceOf(e.msg.sender) <= max_uint256;
    require gem1BalanceOfBuffer + gem1Con.balanceOf(e.msg.sender) <= max_uint256;

    uniswapV3MintCallback@withrevert(e, amt0Owed, amt1Owed, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = e.msg.sender != pool;
    bool revert3 = gem0BalanceOfBuffer < to_mathint(amt0Owed);
    bool revert4 = gem0AllowanceBufferDepositor < to_mathint(amt0Owed);
    bool revert5 = gem1BalanceOfBuffer < to_mathint(amt1Owed);
    bool revert6 = gem1AllowanceBufferDepositor < to_mathint(amt1Owed);

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert revert6 => lastReverted, "revert6 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting deposit
rule deposit(DepositorUniV3.LiquidityParams p) {
    env e;

    require p.gem0 == gem0Con;
    require p.gem1 == gem1Con;
    require p.gem0 == poolCon.gem0();
    require p.gem1 == poolCon.gem1();
    require p.fee  == poolCon.fee();

    address anyAddr;
    address otherAddr;
    address otherAddr2;
    uint24 otherUint24;
    require otherAddr != p.gem0 || otherAddr2 != p.gem1 || otherUint24 != p.fee;

    require e.block.timestamp <= max_uint32;

    address buffer = buffer();
    require buffer != poolCon;

    mathint wardsBefore = wards(anyAddr);
    mathint cap0Gem0Gem1FeeBefore; mathint cap1Gem0Gem1FeeBefore; mathint eraGem0Gem1FeeBefore; mathint due0Gem0Gem1FeeBefore; mathint due1Gem0Gem1FeeBefore; mathint endGem0Gem1FeeBefore;
    cap0Gem0Gem1FeeBefore, cap1Gem0Gem1FeeBefore, eraGem0Gem1FeeBefore, due0Gem0Gem1FeeBefore, due1Gem0Gem1FeeBefore, endGem0Gem1FeeBefore = limits(p.gem0, p.gem1, p.fee);
    mathint cap0OtherBefore; mathint cap1OtherBefore; mathint eraOtherBefore; mathint due0OtherBefore; mathint due1OtherBefore; mathint endOtherBefore;
    cap0OtherBefore, cap1OtherBefore, eraOtherBefore, due0OtherBefore, due1OtherBefore, endOtherBefore = limits(otherAddr, otherAddr2, otherUint24);
    mathint gem0BalanceOfBufferBefore = gem0Con.balanceOf(buffer);
    mathint gem1BalanceOfBufferBefore = gem1Con.balanceOf(buffer);
    mathint gem0BalanceOfPoolBefore   = gem0Con.balanceOf(poolCon);
    mathint gem1BalanceOfPoolBefore   = gem1Con.balanceOf(poolCon);

    require gem0BalanceOfBufferBefore + gem0BalanceOfPoolBefore <= max_uint256;
    require gem1BalanceOfBufferBefore + gem1BalanceOfPoolBefore <= max_uint256;

    mathint amt0 = poolCon.random0();
    mathint amt1 = poolCon.random1();

    mathint liquidity = p.liquidity > 0 ? p.liquidity : getLiquidityForAmtsSummary(poolCon, p.tickLower, p.tickUpper, p.amt0Desired, p.amt1Desired);

    mathint retLiq; mathint retAmt0; mathint retAmt1;
    retLiq, retAmt0, retAmt1 = deposit(e, p);

    mathint wardsAfter = wards(anyAddr);
    mathint cap0Gem0Gem1FeeAfter; mathint cap1Gem0Gem1FeeAfter; mathint eraGem0Gem1FeeAfter; mathint due0Gem0Gem1FeeAfter; mathint due1Gem0Gem1FeeAfter; mathint endGem0Gem1FeeAfter;
    cap0Gem0Gem1FeeAfter, cap1Gem0Gem1FeeAfter, eraGem0Gem1FeeAfter, due0Gem0Gem1FeeAfter, due1Gem0Gem1FeeAfter, endGem0Gem1FeeAfter = limits(p.gem0, p.gem1, p.fee);
    mathint cap0OtherAfter; mathint cap1OtherAfter; mathint eraOtherAfter; mathint due0OtherAfter; mathint due1OtherAfter; mathint endOtherAfter;
    cap0OtherAfter, cap1OtherAfter, eraOtherAfter, due0OtherAfter, due1OtherAfter, endOtherAfter = limits(otherAddr, otherAddr2, otherUint24);
    mathint gem0BalanceOfBufferAfter = gem0Con.balanceOf(buffer);
    mathint gem1BalanceOfBufferAfter = gem1Con.balanceOf(buffer);
    mathint gem0BalanceOfPoolAfter   = gem0Con.balanceOf(poolCon);
    mathint gem1BalanceOfPoolAfter   = gem1Con.balanceOf(poolCon);

    mathint expectedDue0 = (to_mathint(e.block.timestamp) >= endGem0Gem1FeeBefore ? cap0Gem0Gem1FeeBefore : due0Gem0Gem1FeeBefore) - amt0;
    mathint expectedDue1 = (to_mathint(e.block.timestamp) >= endGem0Gem1FeeBefore ? cap1Gem0Gem1FeeBefore : due1Gem0Gem1FeeBefore) - amt1;
    mathint expectedEnd = to_mathint(e.block.timestamp) >= endGem0Gem1FeeBefore ? e.block.timestamp + eraGem0Gem1FeeBefore : endGem0Gem1FeeBefore;

    assert wardsAfter == wardsBefore, "deposit did not keep unchanged every wards[x]";
    assert cap0Gem0Gem1FeeAfter == cap0Gem0Gem1FeeBefore, "deposit did not keep unchanged limits[gem0][gem1][fee].cap0";
    assert cap1Gem0Gem1FeeAfter == cap1Gem0Gem1FeeBefore, "deposit did not keep unchanged limits[gem0][gem1][fee].cap1";
    assert eraGem0Gem1FeeAfter == eraGem0Gem1FeeBefore, "deposit did not keep unchanged limits[gem0][gem1][fee].era";
    assert due0Gem0Gem1FeeAfter == expectedDue0, "deposit did not set limits[gem0][gem1][fee].due0 to the expected value";
    assert due1Gem0Gem1FeeAfter == expectedDue1, "deposit did not set limits[gem0][gem1][fee].due1 to the expected value";
    assert endGem0Gem1FeeAfter == expectedEnd, "deposit did not set limits[gem0][gem1][fee].end to the expected value";
    assert cap0OtherAfter == cap0OtherBefore, "deposit did not keep unchanged the rest of limits[x][y][z].cap0";
    assert cap1OtherAfter == cap1OtherBefore, "deposit did not keep unchanged the rest of limits[x][y][z].cap1";
    assert eraOtherAfter == eraOtherBefore, "deposit did not keep unchanged the rest of limits[x][y][z].era";
    assert due0OtherAfter == due0OtherBefore, "deposit did not keep unchanged the rest of limits[x][y][z].due0";
    assert due1OtherAfter == due1OtherBefore, "deposit did not keep unchanged the rest of limits[x][y][z].due1";
    assert endOtherAfter == endOtherBefore, "deposit did not keep unchanged the rest of limits[x][y][z].end";
    assert gem0BalanceOfBufferAfter == gem0BalanceOfBufferBefore - amt0, "deposit did not decrease gem0.balanceOf(buffer) by amt0";
    assert gem1BalanceOfBufferAfter == gem1BalanceOfBufferBefore - amt1, "deposit did not decrease gem1.balanceOf(buffer) by amt1";
    assert gem0BalanceOfPoolAfter == gem0BalanceOfPoolBefore + amt0, "deposit did not increase gem0.balanceOf(pool) by amt0";
    assert gem1BalanceOfPoolAfter == gem1BalanceOfPoolBefore + amt1, "deposit did not increase gem1.balanceOf(pool) by amt1";
    assert retLiq == liquidity, "deposit did not return the expected liquidity";
    assert retAmt0 == amt0, "deposit did not return the expected amt0";
    assert retAmt1 == amt1, "deposit did not return the expected amt1";
}

// Verify revert rules on deposit
rule deposit_revert(DepositorUniV3.LiquidityParams p) {
    env e;

    require p.gem0 == gem0Con;
    require p.gem1 == gem1Con;
    require p.gem0 == poolCon.gem0();
    require p.gem1 == poolCon.gem1();
    require p.fee  == poolCon.fee();

    require e.block.timestamp <= max_uint32;

    address buffer = buffer();
    require buffer != currentContract;
    require buffer != poolCon;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0xc82cb114));
    mathint wardsSender = wards(e.msg.sender);
    mathint cap0Gem0Gem1Fee; mathint cap1Gem0Gem1Fee; mathint eraGem0Gem1Fee; mathint due0Gem0Gem1Fee; mathint due1Gem0Gem1Fee; mathint endGem0Gem1Fee;
    cap0Gem0Gem1Fee, cap1Gem0Gem1Fee, eraGem0Gem1Fee, due0Gem0Gem1Fee, due1Gem0Gem1Fee, endGem0Gem1Fee = limits(p.gem0, p.gem1, p.fee);
    mathint amt0 = poolCon.random0();
    mathint amt1 = poolCon.random1();
    mathint gem0AllowanceBufferDepositor = gem0Con.allowance(buffer, currentContract);
    mathint gem0BalanceOfBuffer = gem0Con.balanceOf(buffer);
    mathint gem1AllowanceBufferDepositor = gem1Con.allowance(buffer, currentContract);
    mathint gem1BalanceOfBuffer = gem1Con.balanceOf(buffer);
    mathint due0Updated = to_mathint(e.block.timestamp) >= endGem0Gem1Fee ? cap0Gem0Gem1Fee : due0Gem0Gem1Fee;
    mathint due1Updated = to_mathint(e.block.timestamp) >= endGem0Gem1Fee ? cap1Gem0Gem1Fee : due1Gem0Gem1Fee;

    deposit@withrevert(e, p);

    bool revert1  = e.msg.value > 0;
    bool revert2  = !canCall && wardsSender != 1;
    bool revert3  = p.gem0 >= p.gem1;
    bool revert4  = to_mathint(e.block.timestamp) >= endGem0Gem1Fee && e.block.timestamp + eraGem0Gem1Fee > max_uint32;
    bool revert5  = gem0AllowanceBufferDepositor < amt0;
    bool revert6  = gem0BalanceOfBuffer < amt0;
    bool revert7  = gem1AllowanceBufferDepositor < amt1;
    bool revert8  = gem1BalanceOfBuffer < amt1;
    bool revert9  = amt0 < to_mathint(p.amt0Min) || amt1 < to_mathint(p.amt1Min);
    bool revert10 = amt0 > due0Updated || amt1 > due1Updated;

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

// Verify correct storage changes for non reverting withdraw
rule withdraw(DepositorUniV3.LiquidityParams p, bool takeFees) {
    env e;

    require p.gem0 == gem0Con;
    require p.gem1 == gem1Con;
    require p.gem0 == poolCon.gem0();
    require p.gem1 == poolCon.gem1();
    require p.fee  == poolCon.fee();

    require poolCon.random2() >= poolCon.random0();
    require poolCon.random3() >= poolCon.random1();

    address anyAddr;
    address otherAddr;
    address otherAddr2;
    uint24 otherUint24;
    require otherAddr != p.gem0 || otherAddr2 != p.gem1 || otherUint24 != p.fee;

    require e.block.timestamp <= max_uint32;

    address buffer = buffer();
    require buffer != poolCon;

    mathint wardsBefore = wards(anyAddr);
    mathint cap0Gem0Gem1FeeBefore; mathint cap1Gem0Gem1FeeBefore; mathint eraGem0Gem1FeeBefore; mathint due0Gem0Gem1FeeBefore; mathint due1Gem0Gem1FeeBefore; mathint endGem0Gem1FeeBefore;
    cap0Gem0Gem1FeeBefore, cap1Gem0Gem1FeeBefore, eraGem0Gem1FeeBefore, due0Gem0Gem1FeeBefore, due1Gem0Gem1FeeBefore, endGem0Gem1FeeBefore = limits(p.gem0, p.gem1, p.fee);
    mathint cap0OtherBefore; mathint cap1OtherBefore; mathint eraOtherBefore; mathint due0OtherBefore; mathint due1OtherBefore; mathint endOtherBefore;
    cap0OtherBefore, cap1OtherBefore, eraOtherBefore, due0OtherBefore, due1OtherBefore, endOtherBefore = limits(otherAddr, otherAddr2, otherUint24);
    mathint gem0BalanceOfBufferBefore = gem0Con.balanceOf(buffer);
    mathint gem1BalanceOfBufferBefore = gem1Con.balanceOf(buffer);
    mathint gem0BalanceOfPoolBefore   = gem0Con.balanceOf(poolCon);
    mathint gem1BalanceOfPoolBefore   = gem1Con.balanceOf(poolCon);

    require gem0BalanceOfBufferBefore + gem0BalanceOfPoolBefore <= max_uint256;
    require gem1BalanceOfBufferBefore + gem1BalanceOfPoolBefore <= max_uint256;

    mathint amt0 = poolCon.random0();
    mathint amt1 = poolCon.random1();
    mathint col0 = takeFees ? poolCon.random2() : amt0;
    mathint col1 = takeFees ? poolCon.random3() : amt1;

    mathint liquidity = p.liquidity > 0 ? p.liquidity : getLiquidityForAmtsSummary(poolCon, p.tickLower, p.tickUpper, p.amt0Desired, p.amt1Desired);

    mathint retLiq; mathint retAmt0; mathint retAmt1; mathint retFees0; mathint retFees1;
    retLiq, retAmt0, retAmt1, retFees0, retFees1 = withdraw(e, p, takeFees);

    mathint wardsAfter = wards(anyAddr);
    mathint cap0Gem0Gem1FeeAfter; mathint cap1Gem0Gem1FeeAfter; mathint eraGem0Gem1FeeAfter; mathint due0Gem0Gem1FeeAfter; mathint due1Gem0Gem1FeeAfter; mathint endGem0Gem1FeeAfter;
    cap0Gem0Gem1FeeAfter, cap1Gem0Gem1FeeAfter, eraGem0Gem1FeeAfter, due0Gem0Gem1FeeAfter, due1Gem0Gem1FeeAfter, endGem0Gem1FeeAfter = limits(p.gem0, p.gem1, p.fee);
    mathint cap0OtherAfter; mathint cap1OtherAfter; mathint eraOtherAfter; mathint due0OtherAfter; mathint due1OtherAfter; mathint endOtherAfter;
    cap0OtherAfter, cap1OtherAfter, eraOtherAfter, due0OtherAfter, due1OtherAfter, endOtherAfter = limits(otherAddr, otherAddr2, otherUint24);
    mathint gem0BalanceOfBufferAfter = gem0Con.balanceOf(buffer);
    mathint gem1BalanceOfBufferAfter = gem1Con.balanceOf(buffer);
    mathint gem0BalanceOfPoolAfter   = gem0Con.balanceOf(poolCon);
    mathint gem1BalanceOfPoolAfter   = gem1Con.balanceOf(poolCon);

    mathint expectedDue0 = (to_mathint(e.block.timestamp) >= endGem0Gem1FeeBefore ? cap0Gem0Gem1FeeBefore : due0Gem0Gem1FeeBefore) - amt0;
    mathint expectedDue1 = (to_mathint(e.block.timestamp) >= endGem0Gem1FeeBefore ? cap1Gem0Gem1FeeBefore : due1Gem0Gem1FeeBefore) - amt1;
    mathint expectedEnd = to_mathint(e.block.timestamp) >= endGem0Gem1FeeBefore ? e.block.timestamp + eraGem0Gem1FeeBefore : endGem0Gem1FeeBefore;

    assert wardsAfter == wardsBefore, "withdraw did not keep unchanged every wards[x]";
    assert cap0Gem0Gem1FeeAfter == cap0Gem0Gem1FeeBefore, "withdraw did not keep unchanged limits[gem0][gem1][fee].cap0";
    assert cap1Gem0Gem1FeeAfter == cap1Gem0Gem1FeeBefore, "withdraw did not keep unchanged limits[gem0][gem1][fee].cap1";
    assert eraGem0Gem1FeeAfter == eraGem0Gem1FeeBefore, "withdraw did not keep unchanged limits[gem0][gem1][fee].era";
    assert due0Gem0Gem1FeeAfter == expectedDue0, "withdraw did not set limits[gem0][gem1][fee].due0 to the expected value";
    assert due1Gem0Gem1FeeAfter == expectedDue1, "withdraw did not set limits[gem0][gem1][fee].due1 to the expected value";
    assert endGem0Gem1FeeAfter == expectedEnd, "withdraw did not set limits[gem0][gem1][fee].end to the expected value";
    assert cap0OtherAfter == cap0OtherBefore, "withdraw did not keep unchanged the rest of limits[x][y][z].cap0";
    assert cap1OtherAfter == cap1OtherBefore, "withdraw did not keep unchanged the rest of limits[x][y][z].cap1";
    assert eraOtherAfter == eraOtherBefore, "withdraw did not keep unchanged the rest of limits[x][y][z].era";
    assert due0OtherAfter == due0OtherBefore, "withdraw did not keep unchanged the rest of limits[x][y][z].due0";
    assert due1OtherAfter == due1OtherBefore, "withdraw did not keep unchanged the rest of limits[x][y][z].due1";
    assert endOtherAfter == endOtherBefore, "withdraw did not keep unchanged the rest of limits[x][y][z].end";
    assert gem0BalanceOfBufferAfter == gem0BalanceOfBufferBefore + col0, "withdraw did not increase gem0.balanceOf(buffer) by col0";
    assert gem1BalanceOfBufferAfter == gem1BalanceOfBufferBefore + col1, "withdraw did not increase gem1.balanceOf(buffer) by col1";
    assert gem0BalanceOfPoolAfter == gem0BalanceOfPoolBefore - col0, "withdraw did not decrease gem0.balanceOf(pool) by col0";
    assert gem1BalanceOfPoolAfter == gem1BalanceOfPoolBefore - col1, "withdraw did not decrease gem1.balanceOf(pool) by col1";
    assert retLiq == liquidity, "withdraw did not return the expected liquidity";
    assert retAmt0 == amt0, "withdraw did not return the expected amt0";
    assert retAmt1 == amt1, "withdraw did not return the expected amt1";
    assert retFees0 == col0 - amt0, "withdraw did not return the expected col0 - amt0";
    assert retFees1 == col1 - amt1, "withdraw did not return the expected col1 - amt1";
}

// Verify revert rules on withdraw
rule withdraw_revert(DepositorUniV3.LiquidityParams p, bool takeFees) {
    env e;

    require p.gem0 == gem0Con;
    require p.gem1 == gem1Con;
    require p.gem0 == poolCon.gem0();
    require p.gem1 == poolCon.gem1();
    require p.fee  == poolCon.fee();

    require poolCon.random2() >= poolCon.random0();
    require poolCon.random3() >= poolCon.random1();

    require e.block.timestamp <= max_uint32;

    address buffer = buffer();
    require buffer != currentContract;
    require buffer != poolCon;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0xcd8e305c));
    mathint wardsSender = wards(e.msg.sender);
    mathint cap0Gem0Gem1Fee; mathint cap1Gem0Gem1Fee; mathint eraGem0Gem1Fee; mathint due0Gem0Gem1Fee; mathint due1Gem0Gem1Fee; mathint endGem0Gem1Fee;
    cap0Gem0Gem1Fee, cap1Gem0Gem1Fee, eraGem0Gem1Fee, due0Gem0Gem1Fee, due1Gem0Gem1Fee, endGem0Gem1Fee = limits(p.gem0, p.gem1, p.fee);
    mathint amt0 = poolCon.random0();
    mathint amt1 = poolCon.random1();
    mathint col0 = takeFees ? poolCon.random2() : amt0;
    mathint col1 = takeFees ? poolCon.random3() : amt1;
    mathint gem0BalanceOfPool = gem0Con.balanceOf(poolCon);
    mathint gem1BalanceOfPool = gem1Con.balanceOf(poolCon);
    require gem0BalanceOfPool >= col0;
    require gem1BalanceOfPool >= col1;
    mathint due0Updated = to_mathint(e.block.timestamp) >= endGem0Gem1Fee ? cap0Gem0Gem1Fee : due0Gem0Gem1Fee;
    mathint due1Updated = to_mathint(e.block.timestamp) >= endGem0Gem1Fee ? cap1Gem0Gem1Fee : due1Gem0Gem1Fee;

    withdraw@withrevert(e, p, takeFees);

    bool revert1 = e.msg.value > 0;
    bool revert2 = !canCall && wardsSender != 1;
    bool revert3 = p.gem0 >= p.gem1;
    bool revert4 = to_mathint(e.block.timestamp) >= endGem0Gem1Fee && e.block.timestamp + eraGem0Gem1Fee > max_uint32;
    bool revert5 = amt0 < to_mathint(p.amt0Min) || amt1 < to_mathint(p.amt1Min);
    bool revert6 = amt0 > due0Updated || amt1 > due1Updated;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert revert6 => lastReverted, "revert6 failed";
    assert lastReverted => revert1  || revert2 || revert3 ||
                           revert4  || revert5 || revert6, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting collect
rule collect(DepositorUniV3.CollectParams p) {
    env e;

    require p.gem0 == gem0Con;
    require p.gem1 == gem1Con;
    require p.gem0 == poolCon.gem0();
    require p.gem1 == poolCon.gem1();
    require p.fee  == poolCon.fee();

    require poolCon.random2() >= poolCon.random0();
    require poolCon.random3() >= poolCon.random1();

    address anyAddr;
    address anyAddr_2;
    uint24 anyUint24;

    require e.block.timestamp <= max_uint32;

    address buffer = buffer();
    require buffer != poolCon;

    mathint wardsBefore = wards(anyAddr);
    mathint cap0Before; mathint cap1Before; mathint eraBefore; mathint due0Before; mathint due1Before; mathint endBefore;
    cap0Before, cap1Before, eraBefore, due0Before, due1Before, endBefore = limits(anyAddr, anyAddr_2, anyUint24);
    mathint gem0BalanceOfBufferBefore = gem0Con.balanceOf(buffer);
    mathint gem1BalanceOfBufferBefore = gem1Con.balanceOf(buffer);
    mathint gem0BalanceOfPoolBefore   = gem0Con.balanceOf(poolCon);
    mathint gem1BalanceOfPoolBefore   = gem1Con.balanceOf(poolCon);

    require gem0BalanceOfBufferBefore + gem0BalanceOfPoolBefore <= max_uint256;
    require gem1BalanceOfBufferBefore + gem1BalanceOfPoolBefore <= max_uint256;

    mathint fees0 = poolCon.random2();
    mathint fees1 = poolCon.random3();

    mathint retFees0; mathint retFees1;
    retFees0, retFees1 = collect(e, p);

    mathint wardsAfter = wards(anyAddr);
    mathint cap0After; mathint cap1After; mathint eraAfter; mathint due0After; mathint due1After; mathint endAfter;
    cap0After, cap1After, eraAfter, due0After, due1After, endAfter = limits(anyAddr, anyAddr_2, anyUint24);
    mathint gem0BalanceOfBufferAfter = gem0Con.balanceOf(buffer);
    mathint gem1BalanceOfBufferAfter = gem1Con.balanceOf(buffer);
    mathint gem0BalanceOfPoolAfter   = gem0Con.balanceOf(poolCon);
    mathint gem1BalanceOfPoolAfter   = gem1Con.balanceOf(poolCon);

    assert wardsAfter == wardsBefore, "collect did not keep unchanged every wards[x]";
    assert cap0After == cap0Before, "collect did not keep unchanged every limits[x][y][z].cap0";
    assert cap1After == cap1Before, "collect did not keep unchanged every limits[x][y][z].cap1";
    assert eraAfter == eraBefore, "collect did not keep unchanged every limits[x][y][z].era";
    assert due0After == due0Before, "collect did not keep unchanged every limits[x][y][z].due0";
    assert due1After == due1Before, "collect did not keep unchanged every limits[x][y][z].due1";
    assert endAfter == endBefore, "collect did not keep unchanged every limits[x][y][z].end";
    assert gem0BalanceOfBufferAfter == gem0BalanceOfBufferBefore + fees0, "collect did not increase gem0.balanceOf(buffer) by fees0";
    assert gem1BalanceOfBufferAfter == gem1BalanceOfBufferBefore + fees1, "collect did not increase gem1.balanceOf(buffer) by fees1";
    assert gem0BalanceOfPoolAfter == gem0BalanceOfPoolBefore - fees0, "collect did not decrease gem0.balanceOf(pool) by fees0";
    assert gem1BalanceOfPoolAfter == gem1BalanceOfPoolBefore - fees1, "collect did not decrease gem1.balanceOf(pool) by fees1";
    assert retFees0 == fees0, "collect did not return the expected fees0";
    assert retFees1 == fees1, "collect did not return the expected fees1";
}

// Verify revert rules on collect
rule collect_revert(DepositorUniV3.CollectParams p) {
    env e;

    require p.gem0 == gem0Con;
    require p.gem1 == gem1Con;
    require p.gem0 == poolCon.gem0();
    require p.gem1 == poolCon.gem1();
    require p.fee  == poolCon.fee();

    require poolCon.random2() >= poolCon.random0();
    require poolCon.random3() >= poolCon.random1();

    require e.block.timestamp <= max_uint32;

    address buffer = buffer();
    require buffer != currentContract;
    require buffer != poolCon;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0x4ead5ba3));
    mathint wardsSender = wards(e.msg.sender);
    mathint fees0 = poolCon.random2();
    mathint fees1 = poolCon.random3();
    mathint gem0BalanceOfPool = gem0Con.balanceOf(poolCon);
    mathint gem1BalanceOfPool = gem1Con.balanceOf(poolCon);
    require gem0BalanceOfPool >= fees0;
    require gem1BalanceOfPool >= fees1;

    collect@withrevert(e, p);

    bool revert1 = e.msg.value > 0;
    bool revert2 = !canCall && wardsSender != 1;
    bool revert3 = p.gem0 >= p.gem1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert lastReverted => revert1  || revert2 || revert3, "Revert rules are not covering all the cases";
}
