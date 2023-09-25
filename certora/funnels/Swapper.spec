// Swapper.spec

using AllocatorRoles as roles;
using Gem0Mock as srcCon;
using Gem1Mock as dstCon;
using CalleeMock as calleeCon;

methods {
    function ilk() external returns (bytes32) envfree;
    function buffer() external returns (address) envfree;
    function wards(address) external returns (uint256) envfree;
    function limits(address, address) external returns (uint96, uint32, uint96, uint32) envfree;
    function roles.canCall(bytes32, address, address, bytes4) external returns (bool) envfree;
    function _.swapCallback(address, address, uint256, uint256, address, bytes) external => DISPATCHER(true) UNRESOLVED;
    function _.allowance(address, address) external => DISPATCHER(true) UNRESOLVED;
    function _.balanceOf(address) external => DISPATCHER(true) UNRESOLVED;
    function _.transfer(address, uint256) external => DISPATCHER(true) UNRESOLVED;
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true) UNRESOLVED;
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;
    address anyAddr;
    address anyAddr_2;

    mathint wardsOtherBefore = wards(other);
    mathint capBefore; mathint eraBefore; mathint dueBefore; mathint endBefore;
    capBefore, eraBefore, dueBefore, endBefore = limits(anyAddr, anyAddr_2);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint capAfter; mathint eraAfter; mathint dueAfter; mathint endAfter;
    capAfter, eraAfter, dueAfter, endAfter = limits(anyAddr, anyAddr_2);

    assert wardsUsrAfter == 1, "rely did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "rely did not keep unchanged the rest of wards[x]";
    assert capAfter == capBefore, "rely did not keep unchanged every limits[x][y].cap";
    assert eraAfter == eraBefore, "rely did not keep unchanged every limits[x][y].era";
    assert dueAfter == dueBefore, "rely did not keep unchanged every limits[x][y].due";
    assert endAfter == endBefore, "rely did not keep unchanged every limits[x][y].end";
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

    mathint wardsOtherBefore = wards(other);
    mathint capBefore; mathint eraBefore; mathint dueBefore; mathint endBefore;
    capBefore, eraBefore, dueBefore, endBefore = limits(anyAddr, anyAddr_2);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    mathint capAfter; mathint eraAfter; mathint dueAfter; mathint endAfter;
    capAfter, eraAfter, dueAfter, endAfter = limits(anyAddr, anyAddr_2);

    assert wardsUsrAfter == 0, "deny did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "deny did not keep unchanged the rest of wards[x]";
    assert capAfter == capBefore, "deny did not keep unchanged every limits[x][y].cap";
    assert eraAfter == eraBefore, "deny did not keep unchanged every limits[x][y].era";
    assert dueAfter == dueBefore, "deny did not keep unchanged every limits[x][y].due";
    assert endAfter == endBefore, "deny did not keep unchanged every limits[x][y].end";
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
rule setLimits(address src, address dst, uint96 cap, uint32 era) {
    env e;

    address anyAddr;
    address otherAddr;
    address otherAddr_2;
    require otherAddr != src || otherAddr_2 != dst;

    mathint wardsBefore = wards(anyAddr);
    mathint capOtherBefore; mathint eraOtherBefore; mathint dueOtherBefore; mathint endOtherBefore;
    capOtherBefore, eraOtherBefore, dueOtherBefore, endOtherBefore = limits(otherAddr, otherAddr_2);

    setLimits(e, src, dst, cap, era);

    mathint wardsAfter = wards(anyAddr);
    mathint capSrcDstAfter; mathint eraSrcDstAfter; mathint dueSrcDstAfter; mathint endSrcDstAfter;
    capSrcDstAfter, eraSrcDstAfter, dueSrcDstAfter, endSrcDstAfter = limits(src, dst);
    mathint capOtherAfter; mathint eraOtherAfter; mathint dueOtherAfter; mathint endOtherAfter;
    capOtherAfter, eraOtherAfter, dueOtherAfter, endOtherAfter = limits(otherAddr, otherAddr_2);

    assert wardsAfter == wardsBefore, "setLimits did not keep unchanged every wards[x]";
    assert capSrcDstAfter == to_mathint(cap), "setLimits did not set limits[src][dst].cap to cap";
    assert eraSrcDstAfter == to_mathint(era), "setLimits did not set limits[src][dst].era to era";
    assert dueSrcDstAfter == 0, "setLimits did not set limits[src][dst].due to 0";
    assert endSrcDstAfter == 0, "setLimits did not set limits[src][dst].end to 0";
    assert capOtherAfter == capOtherBefore, "setLimits did not keep unchanged the rest of limits[x][y].cap";
    assert eraOtherAfter == eraOtherBefore, "setLimits did not keep unchanged the rest of limits[x][y].era";
    assert dueOtherAfter == dueOtherBefore, "setLimits did not keep unchanged the rest of limits[x][y].due";
    assert endOtherAfter == endOtherBefore, "setLimits did not keep unchanged the rest of limits[x][y].end";
}

// Verify revert rules on setLimits
rule setLimits_revert(address src, address dst, uint96 cap, uint32 era) {
    env e;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0xf1b8ac2e));
    mathint wardsSender = wards(e.msg.sender);

    setLimits@withrevert(e, src, dst, cap, era);

    bool revert1 = e.msg.value > 0;
    bool revert2 = !canCall && wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting swap
rule swap(address src, address dst, uint256 amt, uint256 minOut, address callee, bytes data) {
    env e;

    require src == srcCon;
    require dst == dstCon;
    require callee == calleeCon;

    address anyAddr;
    address otherAddr;
    address otherAddr_2;
    require otherAddr != src || otherAddr_2 != dst;

    require e.block.timestamp <= max_uint32;

    address buffer = buffer();
    require buffer != currentContract;
    require buffer != callee;

    mathint wardsBefore = wards(anyAddr);
    mathint capBefore; mathint eraBefore; mathint dueBefore; mathint endBefore;
    capBefore, eraBefore, dueBefore, endBefore = limits(src, dst);
    mathint capOtherBefore; mathint eraOtherBefore; mathint dueOtherBefore; mathint endOtherBefore;
    capOtherBefore, eraOtherBefore, dueOtherBefore, endOtherBefore = limits(otherAddr, otherAddr_2);
    mathint srcBalanceOfBufferBefore = srcCon.balanceOf(e, buffer);
    mathint dstBalanceOfBufferBefore = dstCon.balanceOf(e, buffer);

    require dstBalanceOfBufferBefore + dstCon.balanceOf(e, currentContract) + dstCon.balanceOf(e, callee) <= max_uint256;

    swap(e, src, dst, amt, minOut, callee, data);

    mathint wardsAfter = wards(anyAddr);
    mathint capAfter; mathint eraAfter; mathint dueAfter; mathint endAfter;
    capAfter, eraAfter, dueAfter, endAfter = limits(src, dst);
    mathint capOtherAfter; mathint eraOtherAfter; mathint dueOtherAfter; mathint endOtherAfter;
    capOtherAfter, eraOtherAfter, dueOtherAfter, endOtherAfter = limits(otherAddr, otherAddr_2);

    mathint expectedDue = (to_mathint(e.block.timestamp) >= endBefore ? capBefore : dueBefore) - amt;
    mathint expectedEnd = to_mathint(e.block.timestamp) >= endBefore ? e.block.timestamp + eraBefore : endBefore;
    mathint srcBalanceOfBufferAfter = srcCon.balanceOf(e, buffer);
    mathint dstBalanceOfBufferAfter = dstCon.balanceOf(e, buffer);

    assert wardsAfter == wardsBefore, "swap did not keep unchanged every wards[x]";
    assert capAfter == capBefore, "swap did not keep unchanged limits[src][dst].cap";
    assert eraAfter == eraBefore, "swap did not keep unchanged limits[src][dst].era";
    assert dueAfter == expectedDue, "swap did not set limits[src][dst].due to expected value";
    assert endAfter == expectedEnd, "swap did not set limits[src][dst].end to expected value";
    assert capOtherAfter == capOtherBefore, "swap did not keep unchanged the rest of limits[x][y].cap";
    assert eraOtherAfter == eraOtherBefore, "swap did not keep unchanged the rest of limits[x][y].era";
    assert dueOtherAfter == dueOtherBefore, "swap did not keep unchanged the rest of limits[x][y].due";
    assert endOtherAfter == endOtherBefore, "swap did not keep unchanged the rest of limits[x][y].end";
    assert srcBalanceOfBufferAfter == srcBalanceOfBufferBefore - amt, "swap did not decrease src.balanceOf(buffer) by amt";
    assert dstBalanceOfBufferAfter >= dstBalanceOfBufferBefore + minOut, "swap did not increase dst.balanceOf(buffer) by at least minOut";
}

// Verify revert rules on swap
rule swap_revert(address src, address dst, uint256 amt, uint256 minOut, address callee, bytes data) {
    env e;

    require src == srcCon;
    require dst == dstCon;
    require callee == calleeCon;

    require data.length < max_uint32;
    require e.block.timestamp <= max_uint32;

    address buffer = buffer();
    require buffer != currentContract;

    bool canCall = roles.canCall(ilk(), e.msg.sender, currentContract, to_bytes4(0xb69cbf9f));
    mathint wardsSender = wards(e.msg.sender);
    mathint cap; mathint era; mathint due; mathint end;
    cap, era, due, end = limits(src, dst);
    mathint dueUpdated = to_mathint(e.block.timestamp) >= end ? cap : due;
    mathint srcBalanceOfBuffer = srcCon.balanceOf(e, buffer);
    mathint srcAllowanceBufferSwapper = srcCon.allowance(e, buffer, currentContract);
    mathint dstBalanceOfBuffer = dstCon.balanceOf(e, buffer);
    mathint dstBalanceOfSwapper = dstCon.balanceOf(e, currentContract);
    mathint dstBalanceOfCallee = dstCon.balanceOf(e, callee);
    require dstBalanceOfBuffer + dstBalanceOfSwapper + dstBalanceOfCallee <= max_uint256;

    swap@withrevert(e, src, dst, amt, minOut, callee, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = !canCall && wardsSender != 1;
    bool revert3 = to_mathint(e.block.timestamp) >= end && e.block.timestamp + era > max_uint32;
    bool revert4 = to_mathint(amt) > dueUpdated;
    bool revert5 = srcBalanceOfBuffer < to_mathint(amt);
    bool revert6 = srcAllowanceBufferSwapper < to_mathint(amt);
    bool revert7 = dstBalanceOfSwapper + dstBalanceOfCallee < to_mathint(minOut);

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert revert6 => lastReverted, "revert6 failed";
    assert revert7 => lastReverted, "revert7 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6 ||
                           revert7, "Revert rules are not covering all the cases";
}
