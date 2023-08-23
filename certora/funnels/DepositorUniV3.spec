// DepositorUniV3.spec

using AllocatorRoles as roles;
using PoolUniV3Mock as poolCon;
using Gem0Mock as gem0Con;
using Gem1Mock as gem1Con;

methods {
    function ilk() external returns (bytes32) envfree;
    function buffer() external returns (address) envfree;
    function wards(address) external returns (uint256) envfree;
    function limits(address, address, uint24) external returns (uint96, uint96, uint32, uint96, uint96, uint32) envfree;
    function _getLiquidityForAmts(address pool, int24 tickLower, int24 tickUpper, uint256 amt0Desired, uint256 amt1Desired) internal returns (uint128) => getLiquidityForAmtsSummary(pool, tickLower, tickUpper, amt0Desired, amt1Desired);
    function roles.canCall(bytes32, address, address, bytes4) external returns (bool) envfree;
    function _.mint(address, int24, int24, uint128, bytes) external => DISPATCHER(true);
    function _.uniswapV3MintCallback(uint256, uint256, bytes) external => DISPATCHER(true);
    function poolCon.gem0() external returns (address) envfree;
    function poolCon.gem1() external returns (address) envfree;
    function poolCon.fee() external returns (uint24) envfree;
    function poolCon.random0() external returns (uint256) envfree;
    function poolCon.random1() external returns (uint256) envfree;
    // function _.allowance(address, address) external => DISPATCHER(true) UNRESOLVED;
    // function _.balanceOf(address) external => DISPATCHER(true) UNRESOLVED;
    // function _.transfer(address, uint256) external => DISPATCHER(true) UNRESOLVED;
    function gem0Con.balanceOf(address) external returns (uint256) envfree;
    function gem1Con.balanceOf(address) external returns (uint256) envfree;
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true) UNRESOLVED;
}

ghost mapping(address => mapping(int24 => mapping(int24 => mapping(uint256 => mapping(uint256 => uint128))))) _liquidityMap;

function getLiquidityForAmtsSummary(address pool, int24 tickLower, int24 tickUpper, uint256 amt0Desired, uint256 amt1Desired) returns uint128 {
    return _liquidityMap[pool][tickLower][tickUpper][amt0Desired][amt1Desired];
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;
    address anyAddr;
    address anyAddr2;
    uint24 anyUint24;

    mathint wardsOtherBefore = wards(other);
    mathint cap0Before; mathint cap1Before; mathint eraBefore; mathint due0Before; mathint due1Before; mathint endBefore;
    cap0Before, cap1Before, eraBefore, due0Before, due1Before, endBefore = limits(anyAddr, anyAddr2, anyUint24);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint cap0After; mathint cap1After; mathint eraAfter; mathint due0After; mathint due1After; mathint endAfter;
    cap0After, cap1After, eraAfter, due0After, due1After, endAfter = limits(anyAddr, anyAddr2, anyUint24);

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
    address anyAddr2;
    uint24 anyUint24;

    mathint wardsOtherBefore = wards(other);
    mathint cap0Before; mathint cap1Before; mathint eraBefore; mathint due0Before; mathint due1Before; mathint endBefore;
    cap0Before, cap1Before, eraBefore, due0Before, due1Before, endBefore = limits(anyAddr, anyAddr2, anyUint24);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint cap0After; mathint cap1After; mathint eraAfter; mathint due0After; mathint due1After; mathint endAfter;
    cap0After, cap1After, eraAfter, due0After, due1After, endAfter = limits(anyAddr, anyAddr2, anyUint24);

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
    assert cap1OtherAfter == cap1OtherBefore, "setLimits did not keep unchanged the rest of limits[x][y][z].cap0";
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

    deposit(e, p);

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
    assert cap1OtherAfter == cap1OtherBefore, "deposit did not keep unchanged the rest of limits[x][y][z].cap0";
    assert eraOtherAfter == eraOtherBefore, "deposit did not keep unchanged the rest of limits[x][y][z].era";
    assert due0OtherAfter == due0OtherBefore, "deposit did not keep unchanged the rest of limits[x][y][z].due0";
    assert due1OtherAfter == due1OtherBefore, "deposit did not keep unchanged the rest of limits[x][y][z].due1";
    assert endOtherAfter == endOtherBefore, "deposit did not keep unchanged the rest of limits[x][y][z].end";
    assert gem0BalanceOfBufferAfter == gem0BalanceOfBufferBefore - amt0, "deposit did not decrease gem0.balanceOf(buffer) by amt0";
    assert gem1BalanceOfBufferAfter == gem1BalanceOfBufferBefore - amt1, "deposit did not decrease gem1.balanceOf(buffer) by amt1";
    assert gem0BalanceOfPoolAfter == gem0BalanceOfPoolBefore + amt0, "deposit did not increase gem0.balanceOf(pool) by amt0";
    assert gem1BalanceOfPoolAfter == gem1BalanceOfPoolBefore + amt1, "deposit did not increase gem1.balanceOf(pool) by amt1";
}
